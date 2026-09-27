# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module ICS
    class RecurrenceTest < ActiveSupport::TestCase
      WINDOW_START = Time.utc(2025, 1, 1)
      WINDOW_END = Time.utc(2025, 12, 31, 23, 59, 59)

      def parse(*vevent_lines, time_zone: "America/New_York", window_start: WINDOW_START, window_end: WINDOW_END)
        body = (["BEGIN:VCALENDAR", "VERSION:2.0"] + vevent_lines + ["END:VCALENDAR"]).join("\r\n")
        Parser.new(body, default_time_zone: time_zone, window_start: window_start, window_end: window_end).events
      end

      def series(rrule, dtstart: "DTSTART;TZID=America/New_York:20250106T090000", dtend: "DTEND;TZID=America/New_York:20250106T100000", extra: [])
        ["BEGIN:VEVENT", "UID:series-1", "SUMMARY:Series", dtstart, dtend, "RRULE:#{rrule}", *extra, "END:VEVENT"]
      end

      def local_starts(events, zone = "America/New_York")
        events.map { |event| event.starts_at.in_time_zone(zone).strftime("%Y-%m-%d %H:%M") }
      end

      test "expands weekly BYDAY with COUNT and keeps wall-clock time across DST" do
        events = parse(*series("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4", dtstart: "DTSTART;TZID=America/New_York:20250303T090000", dtend: "DTEND;TZID=America/New_York:20250303T100000"))

        assert_equal(["2025-03-03 09:00", "2025-03-05 09:00", "2025-03-10 09:00", "2025-03-12 09:00"], local_starts(events))
        assert_equal(1.hour, events.last.ends_at - events.last.starts_at)
        # 2025-03-09 is the DST switch; 09:00 EDT is 13:00 UTC.
        assert_equal(Time.utc(2025, 3, 10, 13), events.third.starts_at.utc)
      end

      test "occurrence external ids combine uid and UTC start" do
        events = parse(*series("FREQ=DAILY;COUNT=2"))

        assert_equal(["series-1::20250106T140000Z", "series-1::20250107T140000Z"], events.map(&:uid))
      end

      test "daily with INTERVAL and UNTIL" do
        events = parse(*series("FREQ=DAILY;INTERVAL=2;UNTIL=20250112T235959Z"))

        assert_equal(["2025-01-06 09:00", "2025-01-08 09:00", "2025-01-10 09:00", "2025-01-12 09:00"], local_starts(events))
      end

      test "monthly BYMONTHDAY including negative days" do
        events = parse(*series("FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3", dtstart: "DTSTART;TZID=America/New_York:20250131T090000", dtend: "DTEND;TZID=America/New_York:20250131T100000"))

        assert_equal(["2025-01-31 09:00", "2025-02-28 09:00", "2025-03-31 09:00"], local_starts(events))
      end

      test "monthly on nth weekday" do
        events = parse(*series("FREQ=MONTHLY;BYDAY=2TU;COUNT=3", dtstart: "DTSTART;TZID=America/New_York:20250114T090000", dtend: "DTEND;TZID=America/New_York:20250114T100000"))

        assert_equal(["2025-01-14 09:00", "2025-02-11 09:00", "2025-03-11 09:00"], local_starts(events))
      end

      test "monthly on the last Friday" do
        events = parse(*series("FREQ=MONTHLY;BYDAY=-1FR;COUNT=2", dtstart: "DTSTART;TZID=America/New_York:20250131T090000", dtend: "DTEND;TZID=America/New_York:20250131T100000"))

        assert_equal(["2025-01-31 09:00", "2025-02-28 09:00"], local_starts(events))
      end

      test "monthly skips months without the start day" do
        events = parse(*series("FREQ=MONTHLY;COUNT=3", dtstart: "DTSTART;TZID=America/New_York:20250131T090000", dtend: "DTEND;TZID=America/New_York:20250131T100000"))

        assert_equal(["2025-01-31 09:00", "2025-03-31 09:00", "2025-05-31 09:00"], local_starts(events))
      end

      test "yearly with BYMONTH" do
        events = parse(
          *series("FREQ=YEARLY;BYMONTH=1,7;COUNT=3", dtstart: "DTSTART;TZID=America/New_York:20250106T090000"),
          window_end: Time.utc(2027, 1, 1),
        )

        assert_equal(["2025-01-06 09:00", "2025-07-06 09:00", "2026-01-06 09:00"], local_starts(events))
      end

      test "EXDATE removes occurrences" do
        events = parse(*series("FREQ=DAILY;COUNT=4", extra: ["EXDATE;TZID=America/New_York:20250107T090000,20250108T090000"]))

        assert_equal(["2025-01-06 09:00", "2025-01-09 09:00"], local_starts(events))
      end

      test "RDATE adds occurrences" do
        events = parse(*series("FREQ=DAILY;COUNT=1", extra: ["RDATE;TZID=America/New_York:20250120T150000"]))

        assert_equal(["2025-01-06 09:00", "2025-01-20 15:00"], local_starts(events))
      end

      test "RECURRENCE-ID overrides replace the matching occurrence" do
        override = [
          "BEGIN:VEVENT",
          "UID:series-1",
          "RECURRENCE-ID;TZID=America/New_York:20250107T090000",
          "SUMMARY:Moved",
          "DTSTART;TZID=America/New_York:20250107T150000",
          "DTEND;TZID=America/New_York:20250107T160000",
          "END:VEVENT",
        ]
        events = parse(*series("FREQ=DAILY;COUNT=3"), *override)

        moved = events.find { |event| event.summary == "Moved" }

        assert_equal(3, events.size)
        assert_equal("series-1::20250107T140000Z", moved.uid)
        assert_equal("2025-01-07 15:00", moved.starts_at.in_time_zone("America/New_York").strftime("%Y-%m-%d %H:%M"))
      end

      test "cancelled RECURRENCE-ID overrides remove the occurrence" do
        override = [
          "BEGIN:VEVENT",
          "UID:series-1",
          "RECURRENCE-ID;TZID=America/New_York:20250107T090000",
          "STATUS:CANCELLED",
          "DTSTART;TZID=America/New_York:20250107T090000",
          "END:VEVENT",
        ]
        events = parse(*series("FREQ=DAILY;COUNT=3"), *override)

        assert_equal(["2025-01-06 09:00", "2025-01-08 09:00"], local_starts(events))
      end

      test "series that started before the window still produces in-window occurrences" do
        events = parse(
          *series("FREQ=WEEKLY", dtstart: "DTSTART;TZID=America/New_York:20200106T090000", dtend: "DTEND;TZID=America/New_York:20200106T100000"),
          window_start: Time.utc(2025, 1, 1),
          window_end: Time.utc(2025, 1, 31),
        )

        assert_equal(["2025-01-06 09:00", "2025-01-13 09:00", "2025-01-20 09:00", "2025-01-27 09:00"], local_starts(events))
      end

      test "COUNT is applied from DTSTART, not from the window start" do
        events = parse(
          *series("FREQ=DAILY;COUNT=5"),
          window_start: Time.utc(2025, 1, 9),
          window_end: Time.utc(2025, 1, 31),
        )

        assert_equal(["2025-01-09 09:00", "2025-01-10 09:00"], local_starts(events))
      end

      test "open-ended series is bounded by the window end" do
        events = parse(*series("FREQ=DAILY"), window_end: Time.utc(2025, 1, 10, 23))

        assert_equal(5, events.size)
      end

      test "all-day recurring events use date based ids and keep their length" do
        events = parse(
          "BEGIN:VEVENT",
          "UID:allday-series",
          "SUMMARY:Holiday",
          "DTSTART;VALUE=DATE:20250106",
          "DTEND;VALUE=DATE:20250107",
          "RRULE:FREQ=WEEKLY;COUNT=2",
          "END:VEVENT",
          time_zone: "Asia/Tokyo",
        )

        assert_equal(["allday-series::20250106", "allday-series::20250113"], events.map(&:uid))
        assert(events.all?(&:all_day))
        assert_equal(Date.new(2025, 1, 14), events.last.ends_at.in_time_zone("Asia/Tokyo").to_date)
      end

      test "default window is bounded by the lookback and horizon constants" do
        travel_to(Time.utc(2025, 6, 1)) do
          body = ["BEGIN:VCALENDAR", *series("FREQ=DAILY", dtstart: "DTSTART:20200101T100000Z", dtend: "DTEND:20200101T110000Z"), "END:VCALENDAR"].join("\r\n")
          events = Parser.new(body).events

          assert_operator(events.first.starts_at, :>=, Time.current - Parser::RECURRENCE_LOOKBACK)
          assert_operator(events.last.starts_at, :<=, Time.current + Parser::RECURRENCE_HORIZON)
        end
      end
    end
  end
end
