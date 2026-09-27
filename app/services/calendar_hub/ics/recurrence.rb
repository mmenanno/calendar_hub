# frozen_string_literal: true

module CalendarHub
  module ICS
    # Focused RFC 5545 RRULE expander covering what calendar feeds use in
    # practice: FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT, UNTIL,
    # BYDAY (incl. ordinals such as 2MO / -1FR), BYMONTHDAY, BYMONTH, BYSETPOS
    # and WKST, plus EXDATE/RDATE.
    #
    # Occurrences are generated on the wall clock of the series' zone so that
    # a 09:00 meeting stays at 09:00 across DST transitions. Only occurrences
    # starting inside [window_start, window_end] are returned, but COUNT is
    # applied from DTSTART as the RFC requires.
    class Recurrence
      MAX_OCCURRENCES = 1_000
      MAX_PERIODS = 50_000
      WEEKDAYS = { "SU" => 0, "MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6 }.freeze
      SUPPORTED_FREQUENCIES = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].freeze

      attr_reader :dtstart, :zone, :all_day

      # rule:     raw RRULE value (e.g. "FREQ=WEEKLY;BYDAY=MO,WE") or nil
      # dtstart:  TimeWithZone of the first occurrence
      # exdates:  Array of TimeWithZone/Date values to exclude
      # rdates:   Array of TimeWithZone values to add
      def initialize(rule:, dtstart:, zone:, all_day: false, exdates: [], rdates: [])
        @zone = zone
        @dtstart = dtstart.in_time_zone(zone)
        @rule = parse_rule(rule)
        @all_day = all_day
        @exdates = exdates
        @rdates = rdates
      end

      def occurrences(window_start:, window_end:)
        starts = rule_occurrences(window_start, window_end)
        starts.concat(@rdates.map { |time| time.in_time_zone(zone) }.select { |time| time.between?(window_start, window_end) })
        starts.reject! { |time| excluded?(time) }
        starts.uniq(&:to_i).sort.first(MAX_OCCURRENCES)
      end

      private

      attr_reader :rule

      def rule_occurrences(window_start, window_end)
        results = []
        return results if rule.nil?

        unless SUPPORTED_FREQUENCIES.include?(rule[:freq])
          Rails.logger.warn("[ICS::Recurrence] Unsupported FREQ=#{rule[:freq].inspect}; only the first occurrence is used")
          return dtstart.between?(window_start, window_end) ? [dtstart] : []
        end

        count = 0
        # DTSTART is always the first instance of the series.
        count += 1
        results << dtstart if dtstart.between?(window_start, window_end)
        start_date = dtstart.to_date
        last_date = window_end.in_time_zone(zone).to_date

        each_period(last_date) do |dates|
          dates.each do |date|
            next if date <= start_date

            return results if date > last_date || beyond_until?(date)

            time = build_time(date)
            next if time.nil?
            return results if time > window_end || beyond_until?(date, time)

            count += 1
            return results if rule[:count] && count > rule[:count]

            results << time if time >= window_start
            return results if results.size >= MAX_OCCURRENCES
          end
        end
        results
      end

      def each_period(last_date)
        MAX_PERIODS.times do |index|
          period_start = period_start_date(index)
          break if period_start > last_date || beyond_until?(period_start)

          yield(candidates_for_period(index).sort)
        end
      end

      def period_start_date(index)
        step = rule[:interval] * index
        start_date = dtstart.to_date

        case rule[:freq]
        when "DAILY" then start_date + step
        when "WEEKLY" then start_date - ((start_date.wday - rule[:wkst]) % 7) + (7 * step)
        when "MONTHLY" then start_date.beginning_of_month >> step
        when "YEARLY" then Date.new(start_date.year + step, 1, 1)
        end
      end

      def candidates_for_period(index)
        step = rule[:interval] * index
        start_date = dtstart.to_date

        case rule[:freq]
        when "DAILY"
          date = start_date + step
          matches_filters?(date) ? [date] : []
        when "WEEKLY"
          week_start = start_date - ((start_date.wday - rule[:wkst]) % 7) + (7 * step)
          days = (0..6).map { |offset| week_start + offset }
          weekdays = rule[:byday] ? rule[:byday].map(&:last) : [start_date.wday]
          days.select { |day| weekdays.include?(day.wday) && month_allowed?(day) }
        when "MONTHLY"
          first = start_date.beginning_of_month >> step
          month_allowed?(first) ? apply_setpos(month_candidates(first)) : []
        when "YEARLY"
          yearly_candidates(start_date.year + step)
        end
      end

      def yearly_candidates(year)
        start_date = dtstart.to_date
        if rule[:byday] && rule[:bymonth].nil? && rule[:bymonthday].nil?
          range = Date.new(year, 1, 1)..Date.new(year, 12, 31)
          return apply_setpos(weekday_matches(range))
        end

        months = rule[:bymonth] || [start_date.month]
        dates = months.flat_map { |month| month_candidates(Date.new(year, month, 1)) }
        apply_setpos(dates)
      end

      def month_candidates(first)
        last = first.end_of_month
        days = if rule[:bymonthday]
          rule[:bymonthday].filter_map do |day|
            if day.positive?
              first + (day - 1) if day <= last.day
            elsif -day <= last.day
              last + (day + 1)
            end
          end
        elsif rule[:byday].nil?
          day = dtstart.to_date.day
          day <= last.day ? [first + (day - 1)] : []
        end

        if rule[:byday]
          by_weekday = weekday_matches(first..last)
          days = days ? days & by_weekday : by_weekday
        end
        days.uniq
      end

      def weekday_matches(range)
        rule[:byday].flat_map do |ordinal, wday|
          matching = range.select { |date| date.wday == wday }
          if ordinal.nil?
            matching
          else
            [ordinal.positive? ? matching[ordinal - 1] : matching[ordinal]].compact
          end
        end
      end

      def apply_setpos(dates)
        return dates if rule[:bysetpos].nil?

        sorted = dates.uniq.sort
        rule[:bysetpos].filter_map { |pos| pos.positive? ? sorted[pos - 1] : sorted[pos] }
      end

      def matches_filters?(date)
        return false unless month_allowed?(date)
        return false if rule[:bymonthday] && rule[:bymonthday].none? { |day| monthday_matches?(date, day) }
        return false if rule[:byday] && rule[:byday].none? { |_ordinal, wday| date.wday == wday }

        true
      end

      def monthday_matches?(date, day)
        date.day == (day.positive? ? day : date.end_of_month.day + day + 1)
      end

      def month_allowed?(date)
        rule[:bymonth].nil? || rule[:bymonth].include?(date.month)
      end

      def build_time(date)
        if all_day
          zone.local(date.year, date.month, date.day)
        else
          zone.local(date.year, date.month, date.day, dtstart.hour, dtstart.min, dtstart.sec)
        end
      rescue ArgumentError
        nil
      end

      def beyond_until?(date, time = nil)
        until_value = rule[:until]
        return false if until_value.nil?

        if until_value.is_a?(Date)
          date > until_value
        elsif time
          time > until_value
        else
          date > until_value.in_time_zone(zone).to_date
        end
      end

      def excluded?(time)
        @exdates.any? do |exdate|
          if exdate.is_a?(Date) || all_day
            exdate.to_date == time.in_time_zone(zone).to_date
          else
            exdate.to_i == time.to_i
          end
        end
      end

      def parse_rule(value)
        return if value.blank?

        parts = value.to_s.split(";").each_with_object({}) do |part, memo|
          key, raw = part.split("=", 2)
          memo[key.to_s.strip.upcase] = raw.to_s.strip
        end
        return if parts["FREQ"].blank?

        {
          freq: parts["FREQ"].upcase,
          interval: [parts["INTERVAL"].to_i, 1].max,
          count: parts["COUNT"].presence&.to_i,
          until: parse_until(parts["UNTIL"]),
          byday: parse_byday(parts["BYDAY"]),
          bymonthday: parse_int_list(parts["BYMONTHDAY"]),
          bymonth: parse_int_list(parts["BYMONTH"]),
          bysetpos: parse_int_list(parts["BYSETPOS"]),
          wkst: WEEKDAYS.fetch(parts["WKST"].to_s.upcase, 1),
        }
      end

      def parse_byday(value)
        return if value.blank?

        value.split(",").filter_map do |token|
          match = token.strip.upcase.match(/\A([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)\z/)
          next unless match

          [match[1]&.to_i, WEEKDAYS.fetch(match[2])]
        end.presence
      end

      def parse_int_list(value)
        return if value.blank?

        value.split(",").filter_map { |item| Integer(item.strip, exception: false) }.reject(&:zero?).presence
      end

      def parse_until(value)
        return if value.blank?

        if (match = value.match(/\A(\d{4})(\d{2})(\d{2})\z/))
          Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
        elsif (match = value.match(/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)\z/i))
          # Floating UNTIL values are interpreted in the series' zone.
          until_zone = match[7].present? ? ActiveSupport::TimeZone["UTC"] : zone
          until_zone.local(*match[1..6].map(&:to_i))
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
