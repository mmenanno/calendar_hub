# frozen_string_literal: true

module AppleCalendar
  class Client
    DEFAULT_BASE_URL = "https://caldav.icloud.com"
    # Retry-After values above this are capped so one throttled request cannot
    # stall a sync worker for minutes.
    MAX_RETRY_AFTER = 30
    MAX_STATUS_ATTEMPTS = 4
    MAX_NETWORK_ATTEMPTS = 3
    RETRYABLE_STATUSES = [429, 503].freeze
    # How long a failed calendar discovery is remembered by this client, so a
    # missing calendar costs one discovery per sync instead of one per event.
    DISCOVERY_FAILURE_TTL = 5.minutes
    ICS_LINE_LIMIT = 75 # octets, RFC 5545 section 3.1
    ICS_STATUSES = ["confirmed", "tentative", "cancelled"].freeze
    ICS_TEXT_ESCAPES = { "\\" => "\\\\", ";" => "\\;", "," => "\\,", "\n" => "\\n" }.freeze
    RETRYABLE_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      Timeout::Error,
      IOError,
      SocketError,
      OpenSSL::SSL::SSLError,
    ].freeze

    class Error < StandardError
    end

    class CalendarNotFoundError < Error
    end

    # Raised for non-success CalDAV responses; carries the HTTP status.
    class HTTPError < Error
      attr_reader :status, :http_method

      def initialize(message, status:, http_method:)
        super(message)
        @status = status
        @http_method = http_method
      end
    end

    attr_reader :credentials

    def initialize(credentials: default_credentials)
      @credentials = credentials.symbolize_keys
    end

    # payload keys expected: :uid, :summary, :description, :location, :starts_at, :ends_at
    # optional: :all_day, :time_zone, :status, :transparency, :url, :x_props
    def upsert_event(calendar_identifier:, payload:)
      ensure_ready!(calendar_identifier)
      uid = payload[:uid] || raise(ArgumentError, "payload[:uid] required")

      url = build_calendar_object_url(collection_url_for(calendar_identifier), uid)

      body = build_ics(payload)
      headers = { "Content-Type" => "text/calendar; charset=utf-8" }
      # Try create first (If-None-Match: * fails with 412 when resource exists)
      begin
        request(:put, url, headers: headers.merge("If-None-Match" => "*"), body: body)
      rescue HTTPError => exception
        raise unless exception.status == 412

        # Resource exists; attempt update with ETag
        begin
          if (etag = head_etag(url))
            request(:put, url, headers: headers.merge("If-Match" => etag), body: body)
          else
            request(:put, url, headers: headers, body: body)
          end
        rescue HTTPError => retry_error
          raise unless retry_error.status == 412

          # ETag was stale; unconditional PUT as last resort
          request(:put, url, headers: headers, body: body)
        end
      end
      uid
    end

    # Discover all available calendars via CalDAV.
    # Returns an array of hashes: [{ displayname: "Work", identifier: "Work" }, ...]
    def discover_calendars
      raise ArgumentError, "username required" if credentials[:username].blank?
      raise ArgumentError, "app_specific_password required" if credentials[:app_specific_password].blank?

      principal_url = follow_well_known
      home_set = fetch_calendar_home_set(principal_url)
      list_all_calendars(home_set)
    end

    def delete_event(calendar_identifier:, uid:)
      return uid if ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLE_READONLY", nil))

      ensure_ready!(calendar_identifier)
      raise ArgumentError, "uid required" if uid.blank?

      url = build_calendar_object_url(collection_url_for(calendar_identifier), uid)

      begin
        request(:delete, url)
      rescue HTTPError => exception
        # 404/410 are success for DELETE - the event is already gone
        raise unless [404, 410].include?(exception.status)

        Rails.logger.debug { "[AppleCal] DELETE #{uid} returned #{exception.status} - event already deleted" }
      end

      uid
    end

    # True when credentials are configured (without them every call raises).
    def configured?
      credentials[:username].present? && credentials[:app_specific_password].present?
    end

    # Closes persistent CalDAV connections. Call once a batch of requests
    # (e.g. a whole sync) is done.
    def finish
      (@connections || {}).each_value do |http|
        http.finish if http.started?
      rescue IOError
        nil
      end
      @connections = {}
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
      if (error = settings&.credentials_decryption_error)
        raise CalendarHub::CredentialEncryption::DecryptionError, "Apple Calendar credentials (Settings): #{error.message}"
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
    def collection_url_for(identifier)
      cached_collection_url(identifier) || discover_calendar_url(identifier)
    end

    def discover_calendar_url(identifier)
      if (cached = cached_collection_url(identifier))
        return cached
      end

      raise_cached_discovery_failure!(identifier)

      url = begin
        principal_url = follow_well_known
        home_set = fetch_calendar_home_set(principal_url)
        # Return absolute URL on the iCloud cluster host (e.g., pXX-caldav.icloud.com)
        find_calendar_collection(home_set, identifier)
      rescue Error => exception
        remember_discovery_failure(identifier, exception)
        raise
      end
      Rails.cache.write(caldav_cache_key(identifier), url, expires_in: 12.hours)
      url
    end

    def raise_cached_discovery_failure!(identifier)
      failure = (@discovery_failures ||= {})[identifier]
      return if failure.nil?
      raise failure[:error].class, failure[:error].message if failure[:at] > DISCOVERY_FAILURE_TTL.ago

      @discovery_failures.delete(identifier)
    end

    def remember_discovery_failure(identifier, error)
      (@discovery_failures ||= {})[identifier] = { error: error, at: Time.current }
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
      resp = request(:propfind, url, headers: { "Depth" => "0" }, body: propfind_body, allow_redirect: true)
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

    def list_all_calendars(home_set_url)
      body = <<~XML
        <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <cal:supported-calendar-component-set/>
          </d:prop>
        </d:propfind>
      XML
      resp = request(:propfind, home_set_url, headers: { "Depth" => "1", "Content-Type" => "application/xml" }, body: body)
      parse_all_calendar_collections(resp.body)
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
      parse_collections_for_displayname(resp.body, displayname, home_set_url) ||
        raise(CalendarNotFoundError, "Calendar '#{displayname}' not found in iCloud")
    end

    def propfind_body
      "<d:propfind xmlns:d=\"DAV:\"><d:prop><d:current-user-principal/></d:prop></d:propfind>"
    end

    def parse_calendar_home_set(xml)
      doc = Nokogiri::XML(xml)
      node = doc.at_xpath("//cal:calendar-home-set/d:href", { "cal" => "urn:ietf:params:xml:ns:caldav", "d" => "DAV:" })
      raise Error, "calendar-home-set not found" unless node

      URI.join(base_url, node.text).to_s
    end

    def parse_all_calendar_collections(xml)
      doc = Nokogiri::XML(xml)
      ns = { "d" => "DAV:", "cal" => "urn:ietf:params:xml:ns:caldav" }
      calendars = []
      doc.xpath("//d:response", ns).each do |resp|
        display = resp.at_xpath(".//d:displayname", ns)&.text
        next if display.blank?

        types = resp.xpath(".//d:resourcetype/*", ns).map(&:name)
        next if types.exclude?("collection") || types.exclude?("calendar")

        # Only include calendars that support VEVENT (skip Reminders/VTODO-only)
        components = resp.xpath(".//cal:supported-calendar-component-set/cal:comp/@name", ns).map(&:text)
        next if components.any? && components.exclude?("VEVENT")

        calendars << { displayname: display, identifier: display }
      end
      calendars.sort_by { |c| c[:displayname].downcase }
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

    # Returns a persistent Net::HTTP connection for the given host/port,
    # reusing an existing started session when available. This avoids
    # opening a new TCP + TLS handshake for every CalDAV request.
    def persistent_http(host, port, use_ssl)
      @connections ||= {}
      key = "#{host}:#{port}"
      http = @connections[key]

      if http.nil? || !http.started?
        http = Net::HTTP.new(host, port)
        http.use_ssl = use_ssl
        http.open_timeout = 10
        http.read_timeout = 30
        http.keep_alive_timeout = 30
        http.start
        @connections[key] = http
      end

      http
    end

    # Performs a CalDAV request. Only 2xx responses are successful; 3xx is
    # accepted solely where a redirect is expected (allow_redirect: true, used
    # for .well-known discovery) and never for PUT/DELETE.
    def request(method, url, headers: {}, body: nil, allow_redirect: false)
      uri = URI.parse(url)
      http = persistent_http(uri.host, uri.port, uri.scheme == "https")

      klass = Net::HTTPGenericRequest
      req = klass.new(method.to_s.upcase, !body.nil?, true, uri.request_uri)
      req.basic_auth(credentials[:username], credentials[:app_specific_password])
      headers.each { |k, v| req[k] = v }
      req.body = body if body
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      res = perform_with_retries(http, req, uri)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      Rails.logger.info("[AppleCal] #{method.to_s.upcase} #{uri.request_uri} -> #{res.code} in #{duration}ms")
      code = res.code.to_i
      raise HTTPError.new(failure_message(method, uri, res), status: code, http_method: method.to_s.upcase) unless code.between?(200, 299) || (allow_redirect && code.between?(300, 399))

      res
    end

    def failure_message(method, uri, response)
      detail = response.body.to_s[0, 300]
      message = "CalDAV #{method.to_s.upcase} #{uri} failed: #{response.code} #{response.message}"
      message += " (still failing after #{MAX_STATUS_ATTEMPTS} attempts)" if RETRYABLE_STATUSES.include?(response.code.to_i)
      message += " — #{detail}" if detail.present?
      message
    end

    # Retries transient network errors (reconnecting) and 429/503 responses
    # (honouring Retry-After, capped at MAX_RETRY_AFTER). When throttling
    # never clears, the last 429/503 response is returned so #request raises a
    # descriptive HTTPError.
    def perform_with_retries(http, req, uri)
      network_attempts = 0
      status_attempts = 0

      loop do
        begin
          res = http.request(req)
        rescue *RETRYABLE_ERRORS
          network_attempts += 1
          raise if network_attempts >= MAX_NETWORK_ATTEMPTS

          reconnect!(uri)
          sleep(0.2 * network_attempts)
          next
        end

        if RETRYABLE_STATUSES.include?(res.code.to_i) && (status_attempts += 1) < MAX_STATUS_ATTEMPTS
          sleep(retry_delay(res, status_attempts))
          next
        end

        return res
      end
    end

    def retry_delay(response, attempt)
      retry_after = response["Retry-After"].to_i
      base = retry_after.positive? ? retry_after : 0.5 * (2**attempt)
      [base.to_f, MAX_RETRY_AFTER].min + (rand * 0.2)
    end

    # Drop a persistent connection for the given URI's host; the next request
    # on the same Net::HTTP object reconnects.
    def reconnect!(uri)
      key = "#{uri.host}:#{uri.port}"
      return unless @connections&.key?(key)

      begin
        @connections[key].finish
      rescue IOError
        nil
      end
      @connections.delete(key)
    end

    def head_etag(url)
      res = request(:head, url)
      res["ETag"]
    rescue StandardError => exception
      Rails.logger.warn("[AppleCal] head_etag error for #{url}: #{exception.message}")
      nil
    end

    def build_calendar_object_url(collection_url, uid)
      base = if %r{^https?://}.match?(collection_url)
        collection_url
      else
        URI.join(base_url, collection_url).to_s
      end
      base += "/" unless base.end_with?("/")
      URI.join(base, ERB::Util.url_encode("#{uid}.ics")).to_s
    end

    def build_ics(payload)
      uid = sanitize_uid(payload[:uid])
      all_day = payload[:all_day] || false
      summary = (payload[:summary] || payload[:title] || "").to_s
      description = payload[:description].to_s
      location = payload[:location].to_s
      url = strip_control_chars(payload[:url].to_s)
      x_props = (payload[:x_props] || {}).to_h

      lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//CalendarHub//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:#{uid}",
        "DTSTAMP:#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}",
        *date_lines(payload, all_day),
        "SUMMARY:#{escape_ics(summary)}",
      ]
      lines << "DESCRIPTION:#{escape_ics(description)}" if description.present?
      lines << "LOCATION:#{escape_ics(location)}" if location.present?
      lines << "URL:#{url}" if url.present?
      lines << "STATUS:#{payload[:status].to_s.upcase}" if ICS_STATUSES.include?(payload[:status].to_s)
      lines << "TRANSP:#{transparency(payload[:transparency])}" if payload[:transparency].present?
      x_props.each do |name, value|
        property = name.to_s.upcase.gsub(/[^A-Z0-9-]/, "")
        lines << "#{property}:#{escape_ics(value)}" if property.start_with?("X-")
      end
      lines.push("END:VEVENT", "END:VCALENDAR")

      "#{lines.map { |line| fold_line(line) }.join("\r\n")}\r\n"
    end

    # All-day dates come from the event's own zone: formatting a
    # midnight-in-Tokyo instant in UTC (or the server zone) would shift the
    # event to the previous day.
    def date_lines(payload, all_day)
      if all_day
        zone = ActiveSupport::TimeZone[payload[:time_zone].to_s] || Time.zone
        start_date = payload[:starts_at].in_time_zone(zone).to_date
        end_date = payload[:ends_at].in_time_zone(zone).to_date
        end_date = start_date + 1 if end_date <= start_date
        ["DTSTART;VALUE=DATE:#{start_date.strftime("%Y%m%d")}", "DTEND;VALUE=DATE:#{end_date.strftime("%Y%m%d")}"]
      else
        [
          "DTSTART:#{payload[:starts_at].utc.strftime("%Y%m%dT%H%M%SZ")}",
          "DTEND:#{payload[:ends_at].utc.strftime("%Y%m%dT%H%M%SZ")}",
        ]
      end
    end

    def transparency(value)
      value.to_s.casecmp?("transparent") ? "TRANSPARENT" : "OPAQUE"
    end

    # RFC 5545 TEXT escaping: backslash, semicolon, comma and line breaks.
    # Other control characters are not allowed in content lines.
    def escape_ics(text)
      normalized = strip_control_chars(text.to_s.gsub(/\r\n?/, "\n"))
      normalized.gsub(/[\\;,\n]/, ICS_TEXT_ESCAPES)
    end

    def strip_control_chars(text)
      text.gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
    end

    # Folds a content line at 75 octets without splitting UTF-8 characters.
    def fold_line(line)
      return line if line.bytesize <= ICS_LINE_LIMIT

      segments = []
      current = +""
      limit = ICS_LINE_LIMIT
      line.each_char do |char|
        if current.bytesize + char.bytesize > limit
          segments << current
          current = +""
          limit = ICS_LINE_LIMIT - 1 # continuation lines start with a space
        end
        current << char
      end
      segments << current
      segments.join("\r\n ")
    end

    # Sanitize UID to prevent ICS injection via embedded newlines or control characters.
    # UIDs should be opaque identifiers without whitespace or control chars.
    def sanitize_uid(uid)
      uid.to_s.gsub(/[\r\n\t\0]/, "").strip
    end
  end
end
