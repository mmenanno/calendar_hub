# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module ICS
    class ParserCorrectnessTest < ActiveSupport::TestCase
      def parse(body, **)
        Parser.new(body, **).events
      end

      def calendar(*lines)
        (["BEGIN:VCALENDAR", "VERSION:2.0"] + lines + ["END:VCALENDAR"]).join("\r\n")
      end

      test "VALARM and VTIMEZONE properties do not overwrite event fields" do
        body = calendar(
          "BEGIN:VTIMEZONE",
          "TZID:America/New_York",
          "BEGIN:STANDARD",
          "DTSTART:19701101T020000",
          "TZOFFSETFROM:-0400",
          "TZOFFSETTO:-0500",
          "END:STANDARD",
          "END:VTIMEZONE",
          "BEGIN:VEVENT",
          "UID:alarm-1",
          "SUMMARY:Real title",
          "DESCRIPTION:Real description",
          "DTSTART;TZID=America/New_York:20250101T100000",
          "DTEND;TZID=America/New_York:20250101T110000",
          "BEGIN:VALARM",
          "ACTION:DISPLAY",
          "SUMMARY:Alarm summary",
          "DESCRIPTION:Reminder",
          "TRIGGER:-PT15M",
          "END:VALARM",
          "LOCATION:After alarm",
          "END:VEVENT",
        )

        event = parse(body).sole

        assert_equal("Real title", event.summary)
        assert_equal("Real description", event.description)
        assert_equal("After alarm", event.location)
        refute(event.raw_properties.key?("trigger"))
        refute(event.raw_properties.key?("action"))
      end

      test "uses DURATION when DTEND is absent" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:duration-1",
          "SUMMARY:Duration",
          "DTSTART:20250101T100000Z",
          "DURATION:PT1H30M",
          "END:VEVENT",
        )

        event = parse(body).sole

        assert_equal(Time.utc(2025, 1, 1, 11, 30), event.ends_at)
      end

      test "uses day-based DURATION for all-day events" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:duration-2",
          "SUMMARY:Two days",
          "DTSTART;VALUE=DATE:20250101",
          "DURATION:P2D",
          "END:VEVENT",
        )

        event = parse(body, default_time_zone: "America/Toronto").sole

        assert(event.all_day)
        assert_equal(Date.new(2025, 1, 3), event.ends_at.to_date)
      end

      test "unquotes TZID parameter values" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:quoted-tz",
          "SUMMARY:Quoted",
          'DTSTART;TZID="America/Los_Angeles":20250101T100000',
          'DTEND;TZID="America/Los_Angeles":20250101T110000',
          "END:VEVENT",
        )

        event = parse(body).sole

        assert_equal(Time.utc(2025, 1, 1, 18), event.starts_at.utc)
        assert_equal("America/Los_Angeles", event.time_zone)
      end

      test "maps Windows time zone names to IANA zones" do
        {
          "Pacific Standard Time" => Time.utc(2025, 1, 1, 18),
          "Eastern Standard Time" => Time.utc(2025, 1, 1, 15),
          "W. Europe Standard Time" => Time.utc(2025, 1, 1, 9),
          "GMT Standard Time" => Time.utc(2025, 1, 1, 10),
        }.each do |tzid, expected|
          body = calendar(
            "BEGIN:VEVENT",
            "UID:win-#{tzid.parameterize}",
            "SUMMARY:Windows",
            "DTSTART;TZID=#{tzid}:20250101T100000",
            "DTEND;TZID=#{tzid}:20250101T110000",
            "END:VEVENT",
          )

          assert_equal(expected, parse(body).sole.starts_at.utc, tzid)
        end
      end

      test "all Windows zone mappings resolve to known zones" do
        unresolved = WindowsTimeZones::MAP.values.reject { |name| ActiveSupport::TimeZone[name] }

        assert_empty(unresolved)
      end

      test "falls back to VTIMEZONE offsets for unknown TZIDs" do
        body = calendar(
          "BEGIN:VTIMEZONE",
          "TZID:Custom Tokyo",
          "BEGIN:STANDARD",
          "DTSTART:19700101T000000",
          "TZOFFSETFROM:+0900",
          "TZOFFSETTO:+0900",
          "END:STANDARD",
          "END:VTIMEZONE",
          "BEGIN:VEVENT",
          "UID:custom-tz",
          "SUMMARY:Custom",
          "DTSTART;TZID=Custom Tokyo:20250101T100000",
          "DTEND;TZID=Custom Tokyo:20250101T110000",
          "END:VEVENT",
        )

        assert_equal(Time.utc(2025, 1, 1, 1), parse(body).sole.starts_at.utc)
      end

      test "unknown TZID without VTIMEZONE falls back to the default zone and logs" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:unknown",
          "SUMMARY:Unknown",
          "DTSTART;TZID=Mars/Olympus_Mons:20250101T100000",
          "DTEND;TZID=Mars/Olympus_Mons:20250101T110000",
          "END:VEVENT",
        )
        Rails.logger.expects(:warn).with(regexp_matches(%r{Unknown TZID "Mars/Olympus_Mons"})).once

        event = parse(body, default_time_zone: "America/New_York").sole

        assert_equal(Time.utc(2025, 1, 1, 15), event.starts_at.utc)
      end

      test "parses Z times as UTC regardless of the process time zone" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:utc-1",
          "SUMMARY:UTC",
          "DTSTART:20250101T100000Z",
          "DTEND:20250101T110000Z",
          "END:VEVENT",
        )

        original_tz = ENV.fetch("TZ", nil)
        begin
          ENV["TZ"] = "Asia/Tokyo"

          assert_equal(Time.utc(2025, 1, 1, 10), parse(body, default_time_zone: "America/New_York").sole.starts_at)
        ensure
          ENV["TZ"] = original_tz
        end
      end

      test "unfolds lines continued with a space or a tab" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:fold-1",
          "SUMMARY:Long ",
          " title",
          "DESCRIPTION:Tab",
          "\tbed",
          "DTSTART:20250101T100000Z",
          "END:VEVENT",
        )

        event = parse(body).sole

        assert_equal("Long title", event.summary)
        assert_equal("Tabbed", event.description)
      end

      test "unescapes text in a single pass" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:escape-1",
          'SUMMARY:C:\\\\new folder\\, done\\; ok',
          'DESCRIPTION:Line 1\\nLine 2\\NLine 3',
          "DTSTART:20250101T100000Z",
          "END:VEVENT",
        )

        event = parse(body).sole

        assert_equal('C:\\new folder, done; ok', event.summary)
        assert_equal("Line 1\nLine 2\nLine 3", event.description)
      end

      test "forces binary bodies to UTF-8 and scrubs invalid bytes" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:utf8-1",
          "SUMMARY:Café \xFF réunion",
          "DTSTART:20250101T100000Z",
          "END:VEVENT",
        ).b

        event = parse(body).sole

        assert_equal(Encoding::UTF_8, event.summary.encoding)
        assert_predicate(event.summary, :valid_encoding?)
        assert_equal("Café \uFFFD réunion", event.summary)
      end

      test "raw properties are string keyed and exclude core, volatile and parameter data" do
        body = calendar(
          "BEGIN:VEVENT",
          "UID:raw-1",
          "DTSTAMP:20250101T000000Z",
          "LAST-MODIFIED:20250101T000000Z",
          "SEQUENCE:3",
          "SUMMARY:Raw",
          "DTSTART;TZID=America/New_York:20250101T100000",
          "X-PROVIDER-CLIENT:Jane",
          "URL:https://example.com/e/1",
          "END:VEVENT",
        )

        raw = parse(body).sole.raw_properties

        assert_equal({ "x-provider-client" => "Jane", "url" => "https://example.com/e/1" }, raw)
      end

      test "calendar? detects iCalendar documents" do
        assert_predicate(Parser.new(calendar), :calendar?)
        refute_predicate(Parser.new("<html><body>Login</body></html>"), :calendar?)
        refute_predicate(Parser.new(""), :calendar?)
      end
    end
  end
end
