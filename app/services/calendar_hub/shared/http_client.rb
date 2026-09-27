# frozen_string_literal: true

require "faraday"

module CalendarHub
  module Shared
    class HttpClient
      USER_AGENT = "CalendarHub/1.0"
      OPEN_TIMEOUT = 10  # seconds to establish connection
      READ_TIMEOUT = 30  # seconds to receive full response
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
      end

      def initialize(source)
        @source = source
      end

      # Fetches the feed, following up to MAX_REDIRECTS redirects.
      #
      # Returns { status:, body:, changed:, cache_headers: }. Cache validators
      # are returned rather than saved so the caller can persist them only
      # after the sync that used this body succeeded.
      def get_with_caching(url, conditional: true)
        current_url = self.class.normalize_url(url)
        @visited_urls = [current_url]
        origin_host = URI.parse(current_url).host

        (MAX_REDIRECTS + 1).times do
          uri = URI.parse(current_url)
          response = http_client.get(current_url) do |request|
            apply_conditional_headers(request) if conditional
            apply_authentication(request) if send_credentials_to?(uri, origin_host)
          end

          if REDIRECT_STATUSES.include?(response.status)
            current_url = redirect_target(current_url, response)
            next
          end

          return build_result(response)
        end

        raise CalendarHub::Ingestion::Error, "Feed redirected more than #{MAX_REDIRECTS} times"
      rescue Faraday::TimeoutError => exception
        raise CalendarHub::Ingestion::Error, "HTTP request timed out: #{scrub(exception.message)}"
      rescue Faraday::ConnectionFailed => exception
        raise CalendarHub::Ingestion::Error, "HTTP connection failed: #{scrub(exception.message)}"
      rescue Faraday::Error => exception
        raise CalendarHub::Ingestion::Error, "HTTP request failed: #{scrub(exception.message)}"
      rescue URI::Error
        raise CalendarHub::Ingestion::Error, "Feed URL is invalid"
      end

      private

      def build_result(response)
        case response.status
        when 200..299
          { status: :success, body: response.body, changed: true, cache_headers: cache_headers_from(response) }
        when 304
          { status: :not_modified, body: nil, changed: false, cache_headers: nil }
        else
          raise CalendarHub::Ingestion::Error, "HTTP #{response.status}: #{response.reason_phrase}"
        end
      end

      def redirect_target(current_url, response)
        location = response.headers["location"]
        raise CalendarHub::Ingestion::Error, "HTTP #{response.status} redirect without a Location header" if location.blank?

        target = self.class.normalize_url(URI.join(current_url, location).to_s)
        @visited_urls << target
        target
      end

      def http_client
        @http_client ||= Faraday.new do |connection|
          connection.options.open_timeout = OPEN_TIMEOUT
          connection.options.timeout = READ_TIMEOUT
          connection.headers["User-Agent"] = USER_AGENT
          # include_request: false keeps the (secret) feed URL out of errors.
          connection.response(:raise_error, include_request: false)
          connection.adapter(Faraday.default_adapter)
        end
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
