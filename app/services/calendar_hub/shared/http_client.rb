# frozen_string_literal: true

require "faraday"
require "faraday/net_http"

module CalendarHub
  module Shared
    class HttpClient
      USER_AGENT = "CalendarHub/1.0"
      OPEN_TIMEOUT = 10  # seconds to establish connection
      READ_TIMEOUT = 30  # seconds between reads
      # Total budget for one fetch (every redirect hop, headers and body), so
      # a server dripping bytes just under READ_TIMEOUT can't hold a thread.
      REQUEST_DEADLINE = 45
      MAX_BODY_BYTES = 10 * 1024 * 1024
      MAX_BODY_BYTES_ENV_KEY = "CALENDAR_HUB_MAX_FEED_BYTES"
      BLOCK_PRIVATE_ENV_KEY = "CALENDAR_HUB_BLOCK_PRIVATE_FEEDS"
      ALLOWED_SCHEMES = ["http", "https"].freeze
      MAX_REDIRECTS = 5
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      attr_reader :source

      class << self
        # webcal:// and webcals:// are just "subscribe" hints for HTTPS feeds.
        def normalize_url(url)
          url.to_s.strip.sub(%r{\Awebcals?://}i, "https://")
        end

        # Feed URLs often embed secrets in the path or query string, so only
        # the scheme and host are ever shown in logs and error messages.
        def redact_url(url)
          uri = URI.parse(url.to_s)
          uri.host ? "#{uri.scheme}://#{uri.host}/…" : "[feed URL]"
        rescue URI::Error
          "[feed URL]"
        end

        # Lowercased host of a feed URL (after webcal normalization), or nil
        # when the URL can't be parsed.
        def host_for(url)
          URI.parse(normalize_url(url)).host&.downcase.presence
        rescue URI::Error
          nil
        end

        # True when both URLs point at the same host. Unparsable URLs never
        # match, so saved credentials are not carried over to them.
        def same_host?(url, other_url)
          host = host_for(url)
          host.present? && host == host_for(other_url)
        end

        # True for absolute http(s) URLs with a host (webcal is normalized
        # to https first).
        def fetchable_url?(url)
          uri = URI.parse(normalize_url(url))
          ALLOWED_SCHEMES.include?(uri.scheme&.downcase) && uri.host.present?
        rescue URI::Error
          false
        end

        def max_body_bytes
          configured = Integer(ENV.fetch(MAX_BODY_BYTES_ENV_KEY, ""), exception: false)
          configured&.positive? ? configured : MAX_BODY_BYTES
        end

        # Off by default: self-hosters commonly subscribe to feeds on their LAN.
        def block_private_addresses?
          ActiveModel::Type::Boolean.new.cast(ENV[BLOCK_PRIVATE_ENV_KEY].presence) == true
        end
      end

      def initialize(source, deadline: REQUEST_DEADLINE, max_body_bytes: self.class.max_body_bytes,
        block_private_addresses: self.class.block_private_addresses?)
        @source = source
        @deadline = deadline
        @max_body_bytes = max_body_bytes
        @block_private_addresses = block_private_addresses
      end

      # Fetches the feed, following up to MAX_REDIRECTS redirects.
      #
      # Returns { status:, body:, changed:, cache_headers: }. Cache validators
      # are returned rather than saved so the caller can persist them only
      # after the sync that used this body succeeded.
      def get_with_caching(url, conditional: true)
        current_url = self.class.normalize_url(url)
        @visited_urls = [current_url]
        start_deadline!
        origin_host = parse_feed_url(current_url).host

        (MAX_REDIRECTS + 1).times do
          uri = parse_feed_url(current_url)
          response, body = fetch(uri) do |request|
            apply_conditional_headers(request) if conditional
            apply_authentication(request) if send_credentials_to?(uri, origin_host)
          end

          if REDIRECT_STATUSES.include?(response.status)
            current_url = redirect_target(current_url, response)
            next
          end

          return build_result(response, body)
        end

        raise CalendarHub::Ingestion::Error, "Feed redirected more than #{MAX_REDIRECTS} times"
      rescue Faraday::TimeoutError => exception
        raise CalendarHub::Ingestion::FeedConnectionError, "HTTP request timed out: #{scrub(exception.message)}"
      rescue Faraday::ConnectionFailed, Faraday::SSLError => exception
        raise CalendarHub::Ingestion::FeedConnectionError, "HTTP connection failed: #{scrub(exception.message)}"
      rescue Faraday::Error => exception
        raise CalendarHub::Ingestion::FeedHTTPError.new("HTTP request failed: #{scrub(exception.message)}", status: exception.response_status) if exception.response_status

        raise CalendarHub::Ingestion::Error, "HTTP request failed: #{scrub(exception.message)}"
      rescue URI::Error
        raise CalendarHub::Ingestion::InvalidFeedURLError, "Feed URL is invalid"
      end

      private

      def parse_feed_url(url)
        raise CalendarHub::Ingestion::InvalidFeedURLError, "Feed URL must be an http(s) URL" unless self.class.fetchable_url?(url)

        URI.parse(url)
      end

      # One request hop. The body is streamed so the size cap and the overall
      # deadline are enforced while it arrives.
      def fetch(uri, &)
        check_deadline!
        pinned_ip = AddressGuard.validated_address!(uri.hostname, timeout: remaining_time) if @block_private_addresses
        body = String.new(encoding: Encoding::BINARY)

        response = build_connection(pinned_ip: pinned_ip).get(uri.to_s) do |request|
          yield(request)
          request.options.on_data = proc do |chunk, _received_bytes, _env|
            body.append_as_bytes(chunk)
            raise CalendarHub::Ingestion::FeedTooLargeError, "Feed is larger than #{@max_body_bytes} bytes" if body.bytesize > @max_body_bytes

            check_deadline!
          end
        end

        [response, apply_charset(body, response)]
      end

      # Built per hop so each hop can be pinned to its validated address.
      # Net::HTTP#ipaddr= only changes where the socket connects; the Host
      # header, SNI and certificate verification still use the hostname.
      def build_connection(pinned_ip: nil)
        remaining = remaining_time
        Faraday.new do |connection|
          connection.options.open_timeout = [OPEN_TIMEOUT, remaining].min
          connection.options.timeout = [READ_TIMEOUT, remaining].min
          connection.headers["User-Agent"] = USER_AGENT
          # include_request: false keeps the (secret) feed URL out of errors.
          connection.response(:raise_error, include_request: false)
          connection.adapter(:net_http) do |http|
            http.ipaddr = pinned_ip if pinned_ip
          end
        end
      end

      def start_deadline!
        @deadline_at = monotonic_now + @deadline
      end

      def remaining_time
        return @deadline unless @deadline_at

        [@deadline_at - monotonic_now, 0.001].max
      end

      def check_deadline!
        return unless @deadline_at && monotonic_now > @deadline_at

        raise CalendarHub::Ingestion::FeedDeadlineError, "Feed download took longer than #{@deadline} seconds"
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Mirrors what the adapter does for non-streamed bodies.
      def apply_charset(body, response)
        charset = response.headers["content-type"].to_s[/\bcharset=([^;]+)/i, 1]
        return body unless charset

        body.force_encoding(Encoding.find(charset.strip.delete('"')))
      rescue ArgumentError
        body
      end

      def build_result(response, body)
        case response.status
        when 200..299
          { status: :success, body: body, changed: true, cache_headers: cache_headers_from(response) }
        when 304
          { status: :not_modified, body: nil, changed: false, cache_headers: nil }
        else
          raise CalendarHub::Ingestion::FeedHTTPError.new("HTTP #{response.status}: #{response.reason_phrase}", status: response.status)
        end
      end

      def redirect_target(current_url, response)
        location = response.headers["location"]
        raise CalendarHub::Ingestion::Error, "HTTP #{response.status} redirect without a Location header" if location.blank?

        target = self.class.normalize_url(URI.join(current_url, location).to_s)
        @visited_urls << target
        target
      end

      def apply_conditional_headers(request)
        etag = source.settings["etag"] || source.ics_feed_etag
        last_modified = source.settings["last_modified"] || source.ics_feed_last_modified

        request.headers["If-None-Match"] = etag if etag.present?
        request.headers["If-Modified-Since"] = last_modified if last_modified.present?
      end

      def cache_headers_from(response)
        {
          etag: response.headers["etag"].presence,
          last_modified: response.headers["last-modified"].presence,
        }
      end

      # Credentials are only sent over HTTPS to the feed's original host,
      # never to a host we were redirected to and never in cleartext.
      def send_credentials_to?(uri, origin_host)
        uri.scheme == "https" && uri.host == origin_host
      end

      def apply_authentication(request)
        credentials = (source.credentials || {}).with_indifferent_access
        username = credentials[:http_basic_username]
        password = credentials[:http_basic_password]
        return if username.blank? || password.blank?

        request.headers["Authorization"] = Faraday::Utils.basic_header_from(username, password)
      end

      def scrub(message)
        (@visited_urls || []).reduce(message.to_s) do |text, url|
          text.gsub(url, self.class.redact_url(url))
        end
      end
    end
  end
end
