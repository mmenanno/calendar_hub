# frozen_string_literal: true

require "active_support/time"

module CalendarHub
  module ICS
    # Parses an iCalendar document into CalendarHub::ICS::Event values.
    #
    # - Only properties of VEVENT components are read (nested VALARM and
    #   sibling VTIMEZONE components cannot leak into event fields).
    # - Recurring events (RRULE/RDATE) are expanded into individual
    #   occurrences inside a bounded window; each occurrence gets the
    #   external id "<uid>::<occurrence start>" (see .occurrence_id).
    #   RECURRENCE-ID overrides replace generated occurrences and
    #   STATUS:CANCELLED overrides remove them.
    class Parser
      # How far back / ahead recurring series are expanded by default.
      RECURRENCE_LOOKBACK = 30.days
      RECURRENCE_HORIZON = 365.days
      OCCURRENCE_SEPARATOR = "::"

      # Properties mapped to dedicated Event fields (or used for expansion);
      # everything else ends up in raw_properties.
      CORE_PROPERTIES = [
        "UID", "SUMMARY", "DESCRIPTION", "LOCATION", "STATUS", "DTSTART", "DTEND", "DURATION",
        "RRULE", "RDATE", "EXDATE", "EXRULE", "RECURRENCE-ID",
      ].freeze
      # Properties that change on every export without the event changing.
      VOLATILE_PROPERTIES = ["DTSTAMP", "LAST-MODIFIED", "CREATED", "SEQUENCE"].freeze

      DATE_PATTERN = /\A(\d{4})(\d{2})(\d{2})\z/
      DATETIME_PATTERN = /\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)\z/i
      DURATION_PATTERN = /\A([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?\z/i
      TEXT_ESCAPE_PATTERN = /\\([\\;,nN])/

      attr_reader :ics_content, :default_time_zone, :window_start, :window_end

      class << self
        def occurrence_id(uid, starts_at, all_day:)
          key = all_day ? starts_at.to_date.strftime("%Y%m%d") : starts_at.utc.strftime("%Y%m%dT%H%M%SZ")
          "#{uid}#{OCCURRENCE_SEPARATOR}#{key}"
        end

        # The UID of the series an external id belongs to.
        def series_uid(external_id)
          external_id.to_s.split(OCCURRENCE_SEPARATOR, 2).first
        end

        def occurrence?(external_id)
          external_id.to_s.include?(OCCURRENCE_SEPARATOR)
        end
      end

      def initialize(ics_content, default_time_zone: "UTC", window_start: nil, window_end: nil)
        @ics_content = normalize_encoding(ics_content)
        @default_time_zone = default_time_zone
        now = Time.current
        @window_start = window_start || (now - RECURRENCE_LOOKBACK)
        @window_end = window_end || (now + RECURRENCE_HORIZON)
        @zone_cache = {}
      end

      # True when the body looks like an iCalendar document at all.
      def calendar?
        ics_content.match?(/^BEGIN:VCALENDAR\s*$/i)
      end

      def events
        @events ||= build_events
      end

      private

      def normalize_encoding(content)
        text = content.to_s.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub("\uFFFD") unless text.valid_encoding?
        text.delete_prefix("\uFEFF")
      end

      # --- Component parsing -----------------------------------------------

      def build_events
        components = parse_components
        parsed = components.filter_map { |properties| build_component(properties) }
        overrides, masters = parsed.partition { |component| component[:recurrence_id] }
        overrides_by_uid = overrides.group_by { |component| component[:uid] }

        events = masters.flat_map do |master|
          if master[:rrule] || master[:rdates].any?
            expand_series(master, overrides_by_uid.delete(master[:uid]) || [])
          else
            [to_event(master)]
          end
        end

        # Overrides whose master is absent from the feed are emitted on their own.
        overrides_by_uid.each_value do |list|
          list.each do |override|
            next if override[:status] == "cancelled"

            events << to_event(override, uid: self.class.occurrence_id(override[:uid], override[:recurrence_id], all_day: override[:all_day]))
          end
        end

        events
      end

      # Walks the unfolded lines with a component stack and returns the
      # property list of every VEVENT. VTIMEZONE definitions are recorded as a
      # fallback for TZIDs that are neither IANA nor Windows names.
      def parse_components
        stack = []
        vevents = []
        @vtimezones = {}
        current_event = nil
        current_timezone = nil
        current_observance = nil

        unfolded_lines.each do |line|
          name, params, value = parse_line(line)
          next if name.nil?

          case name
          when "BEGIN"
            component = value.strip.upcase
            stack.push(component)
            case component
            when "VEVENT"
              current_event = [] if stack.size <= 2
            when "VTIMEZONE"
              current_timezone = {}
            when "STANDARD", "DAYLIGHT"
              current_observance = component.downcase.to_sym if stack[-2] == "VTIMEZONE"
            end
          when "END"
            component = value.strip.upcase
            index = stack.rindex(component)
            stack.slice!(index..) if index
            case component
            when "VEVENT"
              vevents << current_event if current_event
              current_event = nil
            when "VTIMEZONE"
              @vtimezones[current_timezone[:tzid]] = current_timezone if current_timezone&.dig(:tzid)
              current_timezone = nil
            when "STANDARD", "DAYLIGHT"
              current_observance = nil
            end
          else
            case stack.last
            when "VEVENT"
              current_event&.push([name, params, value])
            when "VTIMEZONE"
              current_timezone[:tzid] = value.strip if name == "TZID" && current_timezone
            when "STANDARD", "DAYLIGHT"
              if name == "TZOFFSETTO" && current_timezone && current_observance
                current_timezone[current_observance] = parse_utc_offset(value)
              end
            end
          end
        end

        vevents
      end

      def build_component(properties)
        component = { rdates: [], exdates: [], raw: {} }

        properties.each do |name, params, value|
          case name
          when "UID" then component[:uid] = value.strip
          when "SUMMARY" then component[:summary] = unescape_text(value)
          when "DESCRIPTION" then component[:description] = unescape_text(value)
          when "LOCATION" then component[:location] = unescape_text(value)
          when "STATUS" then component[:status] = value.strip.downcase
          when "DTSTART"
            component[:dtstart] = parse_datetime(value, params)
            component[:all_day] = date_value?(value, params)
            component[:zone] = component[:all_day] ? default_zone : zone_for(value, params)
          when "DTEND" then component[:dtend] = parse_datetime(value, params)
          when "DURATION" then component[:duration] = value.strip
          when "RRULE" then component[:rrule] = value.strip
          when "RDATE" then component[:rdates].concat(parse_datetime_list(value, params))
          when "EXDATE" then component[:exdates].concat(parse_datetime_list(value, params, keep_dates: true))
          when "RECURRENCE-ID" then component[:recurrence_id] = parse_datetime(value, params)
          else
            next if CORE_PROPERTIES.include?(name) || VOLATILE_PROPERTIES.include?(name)

            component[:raw][name.downcase] = unescape_text(value)
          end
        end

        return if component[:uid].blank? || component[:dtstart].nil?

        component[:ends_at] = compute_end(component)
        component
      end

      def compute_end(component)
        starts_at = component[:dtstart]
        return component[:dtend] if component[:dtend] && component[:dtend] >= starts_at

        if component[:duration] && (ends_at = apply_duration(starts_at, component[:duration]))
          return ends_at
        end

        component[:all_day] ? starts_at + 1.day : starts_at
      end

      def apply_duration(starts_at, value)
        match = DURATION_PATTERN.match(value)
        return if match.nil? || match[1] == "-"

        weeks, days, hours, minutes, seconds = match[2..6].map(&:to_i)
        starts_at + (weeks * 7 + days).days + hours.hours + minutes.minutes + seconds.seconds
      end

      # --- Recurrence ------------------------------------------------------

      def expand_series(master, overrides)
        all_day = master[:all_day]
        zone = master[:zone]
        recurrence = Recurrence.new(
          rule: master[:rrule],
          dtstart: master[:dtstart],
          zone: zone,
          all_day: all_day,
          exdates: master[:exdates],
          rdates: master[:rdates],
        )

        overrides_by_key = overrides.index_by { |override| occurrence_key(override[:recurrence_id], all_day) }
        events = recurrence.occurrences(window_start: window_start, window_end: window_end).filter_map do |start|
          uid = self.class.occurrence_id(master[:uid], start, all_day: all_day)
          override = overrides_by_key.delete(occurrence_key(start, all_day))

          if override
            to_event(override, uid: uid) unless override[:status] == "cancelled"
          else
            to_event(master, uid: uid, starts_at: start, ends_at: occurrence_end(master, start))
          end
        end

        # Overrides that moved an occurrence into the window (or whose original
        # slot was not generated) still describe a real instance.
        overrides_by_key.each_value do |override|
          next if override[:status] == "cancelled"
          next unless override[:dtstart].between?(window_start, window_end)

          events << to_event(override, uid: self.class.occurrence_id(master[:uid], override[:recurrence_id], all_day: all_day))
        end

        events
      end

      def occurrence_end(master, start)
        if master[:all_day]
          days = (master[:ends_at].to_date - master[:dtstart].to_date).to_i
          start + [days, 1].max.days
        else
          start + (master[:ends_at] - master[:dtstart])
        end
      end

      def occurrence_key(time, all_day)
        all_day ? time.to_date.iso8601 : time.to_i
      end

      def to_event(component, uid: component[:uid], starts_at: component[:dtstart], ends_at: component[:ends_at])
        Event.new(
          uid: uid,
          summary: component[:summary],
          description: component[:description],
          location: component[:location],
          starts_at: starts_at,
          ends_at: ends_at,
          status: component[:status] || "confirmed",
          time_zone: (component[:zone] || default_zone).name,
          all_day: component[:all_day],
          raw_properties: component[:raw],
        )
      end

      # --- Lines -----------------------------------------------------------

      # RFC 5545 §3.1: a line starting with a space or horizontal tab
      # continues the previous line.
      def unfolded_lines
        lines = []
        ics_content.split(/\r\n|\n|\r/).each do |line|
          if line.start_with?(" ", "\t") && lines.any?
            lines[-1] = lines.last + line[1..]
          else
            lines << line
          end
        end
        lines.reject(&:empty?)
      end

      # Splits a content line into [NAME, params, value]. Parameter values
      # may be quoted (and then contain ";", ":" or ","); quotes are removed.
      def parse_line(line)
        name_end = line.index(/[;:]/)
        return if name_end.nil?

        name = line[0...name_end].strip.upcase
        params = {}
        index = name_end

        while line[index] == ";"
          equals = line.index("=", index + 1)
          break if equals.nil?

          key = line[(index + 1)...equals].strip.upcase
          index = equals + 1
          values = []
          loop do
            if line[index] == '"'
              closing = line.index('"', index + 1) || line.length
              values << line[(index + 1)...closing]
              index = closing + 1
            else
              stop = line.index(/[;:,]/, index) || line.length
              values << line[index...stop]
              index = stop
            end
            break unless line[index] == ","

            index += 1
          end
          params[key] = values.join(",")
        end

        value = line[index] == ":" ? line[(index + 1)..].to_s : ""
        [name, params, value]
      end

      # Unescape TEXT values in a single pass so "\\n" (escaped backslash
      # followed by n) stays a literal backslash + n.
      def unescape_text(value)
        value.gsub(TEXT_ESCAPE_PATTERN) do
          char = Regexp.last_match(1)
          ["n", "N"].include?(char) ? "\n" : char
        end
      end

      # --- Dates and zones -------------------------------------------------

      def date_value?(value, params)
        params["VALUE"].to_s.casecmp?("DATE") || DATE_PATTERN.match?(value.strip)
      end

      def zone_for(value, params)
        return utc_zone if value.strip.end_with?("Z", "z")

        resolve_zone(params["TZID"]) || default_zone
      end

      # All-day (DATE) values are floating dates and are anchored to the
      # default (source) zone; DATE-TIME values honour a trailing Z or TZID.
      def parse_datetime(value, params)
        value = value.strip
        if (match = DATE_PATTERN.match(value))
          default_zone.local(match[1].to_i, match[2].to_i, match[3].to_i)
        elsif (match = DATETIME_PATTERN.match(value))
          parts = match[1..6].map(&:to_i)
          zone = match[7].present? ? utc_zone : (resolve_zone(params["TZID"]) || default_zone)
          zone.local(*parts)
        else
          default_zone.parse(value)
        end
      rescue ArgumentError
        nil
      end

      def parse_datetime_list(value, params, keep_dates: false)
        value.split(",").filter_map do |item|
          item = item.split("/", 2).first.to_s.strip # PERIOD values: use the start
          if keep_dates && DATE_PATTERN.match?(item)
            match = DATE_PATTERN.match(item)
            Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
          else
            parse_datetime(item, params)
          end
        rescue ArgumentError
          nil
        end
      end

      def resolve_zone(tzid)
        return if tzid.blank?

        @zone_cache.fetch(tzid) { @zone_cache[tzid] = lookup_zone(tzid) }
      end

      def lookup_zone(tzid)
        name = tzid.strip
        candidates = [
          name,
          WindowsTimeZones.iana_for(name),
          # Outlook display names such as "(UTC-05:00) Eastern Time (US & Canada)"
          name.sub(/\A\(UTC[^)]*\)\s*/i, ""),
        ]
        # Prefixed ids such as "/mozilla.org/20050126_1/America/New_York"
        segments = name.split("/").compact_blank
        candidates.concat((1...segments.size).map { |i| segments.last(segments.size - i).join("/") }) if segments.size > 2

        zone = candidates.compact.uniq.lazy.filter_map { |candidate| find_zone(candidate) }.first
        zone ||= zone_from_vtimezone(name)
        Rails.logger.warn("[ICS::Parser] Unknown TZID #{name.inspect}; using #{default_zone.name}") if zone.nil?
        zone
      end

      def find_zone(name)
        return if name.blank?

        ActiveSupport::TimeZone[name]
      rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
        nil
      end

      # Last resort for custom TZIDs: pick the zone whose offsets match the
      # STANDARD/DAYLIGHT offsets declared by the feed's VTIMEZONE.
      def zone_from_vtimezone(tzid)
        definition = @vtimezones&.dig(tzid)
        return if definition.nil?

        standard = definition[:standard] || definition[:daylight]
        daylight = definition[:daylight] || standard
        return if standard.nil?

        expected = [standard, daylight].sort
        year = Time.current.year
        ActiveSupport::TimeZone.all.find do |zone|
          offsets = [Time.utc(year, 1, 15), Time.utc(year, 7, 15)].map { |time| zone.tzinfo.period_for_utc(time).utc_total_offset }
          offsets.sort == expected
        end
      end

      def parse_utc_offset(value)
        match = value.strip.match(/\A([+-])(\d{2})(\d{2})(\d{2})?\z/)
        return if match.nil?

        seconds = (match[2].to_i * 3600) + (match[3].to_i * 60) + match[4].to_i
        match[1] == "-" ? -seconds : seconds
      end

      def default_zone
        @default_zone ||= ActiveSupport::TimeZone[default_time_zone.to_s] || utc_zone
      rescue ArgumentError
        @default_zone = utc_zone
      end

      def utc_zone
        ActiveSupport::TimeZone["UTC"]
      end
    end
  end
end
