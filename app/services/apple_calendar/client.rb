# frozen_string_literal: true

module AppleCalendar
  class Client
    DEFAULT_BASE_URL = "https://caldav.icloud.com"

    attr_reader :credentials

    def initialize(credentials: default_credentials)
      @credentials = credentials.symbolize_keys
    end

    # payload keys expected: :uid, :summary, :description, :location, :starts_at, :ends_at
    def upsert_event(calendar_identifier:, payload:)
      ensure_ready!(calendar_identifier)
      uid = payload[:uid] || raise(ArgumentError, "payload[:uid] required")

      collection_url = cached_collection_url(calendar_identifier) || discover_calendar_url(calendar_identifier)
      url = build_calendar_object_url(collection_url, uid)

      body = build_ics(payload)
      headers = { "Content-Type" => "text/calendar; charset=utf-8" }
      # Try create first
      begin
        request(:put, url, headers: headers.merge("If-None-Match" => "*"), body: body)
      rescue => e
        if e.message.include?(" 412 ")
          # Resource exists; attempt update with ETag
          if (etag = head_etag(url))
            request(:put, url, headers: headers.merge("If-Match" => etag), body: body)
          else
            request(:put, url, headers: headers, body: body)
          end
        else
          raise
        end
      end
      uid
    end

    def delete_event(calendar_identifier:, uid:)
      return uid if ActiveModel::Type::Boolean.new.cast(ENV["APPLE_READONLY"])

      ensure_ready!(calendar_identifier)
      raise ArgumentError, "uid required" if uid.blank?

      collection_url = cached_collection_url(calendar_identifier) || discover_calendar_url(calendar_identifier)
      url = build_calendar_object_url(collection_url, uid)

      begin
        request(:delete, url)
      rescue => e
        # 404 Not Found is actually success for DELETE - the event is already gone
        if e.message.include?(" 404 ")
          Rails.logger.debug { "[AppleCal] DELETE #{uid} returned 404 - event already deleted" }
        else
          raise
        end
      end

      uid
    end

    private

    def ensure_ready!(calendar_identifier)
      raise ArgumentError, "calendar identifier required" if calendar_identifier.blank?
      raise ArgumentError, "username required" if credentials[:username].blank?
      raise ArgumentError, "app_specific_password required" if credentials[:app_specific_password].blank?
    end

    def default_credentials
      settings = begin
        AppSetting.first
      rescue StandardError
        nil
      end
      if settings&.apple_username.present? && settings&.apple_app_password.present?
        { username: settings.apple_username, app_specific_password: settings.apple_app_password }
      else
        {}
      end
    end

    def base_url
      credentials[:base_url].presence || DEFAULT_BASE_URL
    end

    def encoded_path(str)
      str.split("/").map { |s| ERB::Util.url_encode(s) }.join("/")
    end

    # --- Discovery ---------------------------------------------------------
    def discover_calendar_url(identifier)
      if (cached = cached_collection_url(identifier))
        return cached
      end

      url = begin
        principal_url = follow_well_known
        home_set = fetch_calendar_home_set(principal_url)
        # Return absolute URL on the iCloud cluster host (e.g., pXX-caldav.icloud.com)
        find_calendar_collection(home_set, identifier)
      end
      Rails.cache.write(caldav_cache_key(identifier), url, expires_in: 12.hours)
      url
    end

    def cached_collection_url(identifier)
      Rails.cache.read(caldav_cache_key(identifier))
    end

    def caldav_cache_key(identifier)
      ["apple:caldav:collection_url", credentials[:username], identifier].join(":")
    end

    def follow_well_known
      # RFC 6764/.well-known/caldav: servers typically redirect to principal
      url = URI.join(base_url, "/.well-known/caldav").to_s
      resp = request(:propfind, url, headers: { "Depth" => "0" }, body: propfind_body)
      location = resp["Location"]
      location.presence || url
    end

    def fetch_calendar_home_set(principal_url)
      body = <<~XML
        <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <cal:calendar-home-set/>
          </d:prop>
        </d:propfind>
      XML
      resp = request(:propfind, principal_url, headers: { "Depth" => "0", "Content-Type" => "application/xml" }, body: body)
      parse_calendar_home_set(resp.body)
    end

    def find_calendar_collection(home_set_url, displayname)
      body = <<~XML
        <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
          </d:prop>
        </d:propfind>
      XML
      resp = request(:propfind, home_set_url, headers: { "Depth" => "1", "Content-Type" => "application/xml" }, body: body)
      parse_collections_for_displayname(resp.body, displayname, home_set_url) || raise("Calendar '#{displayname}' not found")
    end

    def propfind_body
      "<d:propfind xmlns:d=\"DAV:\"><d:prop><d:current-user-principal/></d:prop></d:propfind>"
    end

    def parse_calendar_home_set(xml)
      doc = Nokogiri::XML(xml)
      node = doc.at_xpath("//cal:calendar-home-set/d:href", { "cal" => "urn:ietf:params:xml:ns:caldav", "d" => "DAV:" })
      raise "calendar-home-set not found" unless node

      URI.join(base_url, node.text).to_s
    end

    def parse_collections_for_displayname(xml, desired, home_set_url)
      doc = Nokogiri::XML(xml)
      ns = { "d" => "DAV:", "cal" => "urn:ietf:params:xml:ns:caldav" }
      doc.xpath("//d:response", ns).each do |resp|
        display = resp.at_xpath(".//d:displayname", ns)&.text
        next if display.blank?

        types = resp.xpath(".//d:resourcetype/*", ns).map(&:name)
        next if types.exclude?("collection") || types.exclude?("calendar")

        next unless display == desired

        href = resp.at_xpath(".//d:href", ns).text
        # iCloud returns an absolute path; join with the principal host from home_set_url
        base = URI.parse(home_set_url)
        return URI.join("#{base.scheme}://#{base.host}", href).to_s
      end
      nil
    end

    # --- HTTP --------------------------------------------------------------
    def request(method, url, headers: {}, body: nil)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      klass = Net::HTTPGenericRequest
      req = klass.new(method.to_s.upcase, !body.nil?, true, uri.request_uri)
      req.basic_auth(credentials[:username], credentials[:app_specific_password])
      headers.each { |k, v| req[k] = v }
      req.body = body if body
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      res = perform_with_retries(http, req, uri)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      Rails.logger.info("[AppleCal] #{method.to_s.upcase} #{uri.request_uri} -> #{res.code} in #{duration}ms")
      unless res.code.to_i.between?(200, 399)
        detail = res.body.to_s[0, 300]
        raise "CalDAV #{method.to_s.upcase} #{uri} failed: #{res.code} #{res.message}#{" — #{detail}" if detail.present?}"
      end
      res
    end

    def perform_with_retries(http, req, uri)
      attempts = 0
      begin
        attempts += 1
        res = http.request(req)
        if res.code.to_i == 429 || res.code.to_i == 503
          wait = (res["Retry-After"].to_i.nonzero? || (0.5 * (2**attempts))).to_f
          sleep(wait + rand * 0.2)
          raise "retry" if attempts < 4
        end
        res
      rescue
        raise if attempts >= 3

        sleep(0.2 * attempts)
        retry
      end
    end

    def head_etag(url)
      res = request(:head, url)
      res["ETag"]
    rescue
      nil
    end

    def build_calendar_object_url(collection_url, uid)
      base = if %r{^https?://}.match?(collection_url)
        collection_url
      else
        URI.join(base_url, collection_url).to_s
      end
      base = base.end_with?("/") ? base : base + "/"
      URI.join(base, ERB::Util.url_encode("#{uid}.ics")).to_s
    end

    def build_ics(payload)
      uid = payload[:uid]
      dtstart = payload[:starts_at].utc.strftime("%Y%m%dT%H%M%SZ")
      dtend   = payload[:ends_at].utc.strftime("%Y%m%dT%H%M%SZ")
      summary = (payload[:summary] || payload[:title] || "").to_s
      description = (payload[:description] || "").to_s
      location = (payload[:location] || "").to_s
      now = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      url = (payload[:url] || "").to_s
      x_props = (payload[:x_props] || {}).to_h

      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//CalendarHub//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        BEGIN:VEVENT
        UID:#{uid}
        DTSTAMP:#{now}
        DTSTART:#{dtstart}
        DTEND:#{dtend}
        SUMMARY:#{escape_ics(summary)}
        DESCRIPTION:#{escape_ics(description)}
        LOCATION:#{escape_ics(location)}
        #{"URL:#{escape_ics(url)}" unless url.empty?}
        #{x_props.map { |k, v| "#{k}:#{escape_ics(v)}" }.join("\n")}
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    def escape_ics(text)
      text.to_s.gsub(/\\|;|,|\n/, "\\\\" => "\\\\", ";" => "\\;", "," => "\\,", "\n" => "\\n")
    end
  end
end
