# frozen_string_literal: true

require "active_support/time"
require "time"

module CalendarHub
  module ICS
    class Parser
      attr_reader :ics_content, :default_time_zone

      def initialize(ics_content, default_time_zone: "UTC")
        @ics_content = ics_content.to_s
        @default_time_zone = default_time_zone
      end

      def events
        @events ||= build_events
      end

      private

      def build_events
        in_event = false
        current_event = {}
        tzid = nil
        events = []

        unfolded_lines.each do |line|
          case line
          when "BEGIN:VEVENT"
            in_event = true
            current_event = {}
            tzid = nil
          when "END:VEVENT"
            in_event = false
            events << build_event(current_event, tzid)
          else
            next unless in_event

            key, params, value = parse_line(line)
            case key
            when "UID"
              current_event[:uid] = value
            when "SUMMARY"
              current_event[:summary] = value
            when "DESCRIPTION"
              current_event[:description] = value
            when "LOCATION"
              current_event[:location] = value
            when "STATUS"
              current_event[:status] = value.downcase
            when "DTSTART"
              tzid ||= params["TZID"]
              current_event[:dtstart] = parse_datetime(value, params)
            when "DTEND"
              tzid ||= params["TZID"]
              current_event[:dtend] = parse_datetime(value, params)
            else
              current_event[key.downcase.to_sym] = value
            end
          end
        end

        events.compact
      end

      def build_event(attributes, tzid)
        return if attributes[:uid].blank? || attributes[:dtstart].blank?

        Event.new(
          uid: attributes[:uid],
          summary: attributes[:summary],
          description: attributes[:description],
          location: attributes[:location],
          starts_at: attributes[:dtstart],
          ends_at: attributes[:dtend] || attributes[:dtstart],
          status: attributes[:status] || "confirmed",
          time_zone: tzid || default_time_zone,
          raw_properties: attributes,
        )
      end

      def unfolded_lines
        lines = []
        buffer = nil

        ics_content.each_line do |raw_line|
          line = raw_line.chomp
          if line.start_with?(" ")
            buffer = (buffer || "") + line[1..]
          else
            lines << buffer if buffer
            buffer = line
          end
        end

        lines << buffer if buffer
        lines
      end

      def parse_line(line)
        key_and_params, value = line.split(":", 2)
        return [line, {}, ""] if value.nil?

        if key_and_params.include?(";")
          key, *param_pairs = key_and_params.split(";")
          params = param_pairs.each_with_object({}) do |pair, memo|
            param_key, param_value = pair.split("=", 2)
            memo[param_key] = param_value
          end
          [key, params, decode_value(value)]
        else
          [key_and_params, {}, decode_value(value)]
        end
      end

      def parse_datetime(value, params)
        tzid = params["TZID"]
        normalized = normalize_datetime_string(value)

        if value.end_with?("Z")
          Time.strptime(value, "%Y%m%dT%H%M%SZ").utc
        elsif tzid && (zone = ActiveSupport::TimeZone[tzid])
          zone.parse(normalized)
        else
          default_zone.parse(normalized)
        end
      rescue ArgumentError
        default_zone.parse(normalized)
      end

      def normalize_datetime_string(value)
        return value if value.include?("-")

        date_part, time_part = value.split("T", 2)
        if time_part
          format("%<year>04d-%<month>02d-%<day>02d %<hour>02d:%<minute>02d:%<second>02d", parsed_components(date_part, time_part))
        else
          format("%<year>04d-%<month>02d-%<day>02d", parsed_components(date_part, "000000"))
        end
      end

      def parsed_components(date_part, time_part)
        {
          year: date_part[0, 4].to_i,
          month: date_part[4, 2].to_i,
          day: date_part[6, 2].to_i,
          hour: time_part[0, 2].to_i,
          minute: time_part[2, 2].to_i,
          second: time_part[4, 2].to_i,
        }
      end

      def default_zone
        @default_zone ||= ActiveSupport::TimeZone[default_time_zone] || ActiveSupport::TimeZone["UTC"]
      end

      def decode_value(value)
        value.gsub("\\n", "\n")
      end
    end
  end
end
