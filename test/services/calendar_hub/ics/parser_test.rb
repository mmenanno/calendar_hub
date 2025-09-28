# frozen_string_literal: true

require "test_helper"

class ParserTest < ActiveSupport::TestCase
  test "parses provider ics file" do
    parser = CalendarHub::ICS::Parser.new(file_fixture("provider.ics").read, default_time_zone: "America/Toronto")
    events = parser.events

    assert_equal 2, events.count

    first = events.first

    assert_equal "prov-123", first.uid
    assert_equal "Initial Consultation", first.summary
    assert_equal Time.find_zone!("America/Toronto").parse("2025-09-22 14:00"), first.starts_at
    assert_equal "confirmed", first.status
    assert_equal(
      {
        uid: "prov-123",
        summary: "Initial Consultation",
        description: "Consultation session with client",
        location: "Studio A",
        status: "confirmed",
        dtstamp: "20250920T150000Z",
        "x-provider-practitioner": "Dr. Smith",
        "x-provider-client": "John Doe",
        "x-provider-treatment": "Massage Therapy",
        "x-provider-notes": "Bring paperwork",
      },
      first.raw_properties.slice(:uid, :summary, :description, :location, :status, :dtstamp, :"x-provider-practitioner", :"x-provider-client", :"x-provider-treatment", :"x-provider-notes"),
    )

    second = events.second

    assert_equal "cancelled", second.status
  end

  test "handles empty ics content" do
    parser = CalendarHub::ICS::Parser.new("")
    events = parser.events

    assert_empty(events)
  end

  test "handles nil ics content" do
    parser = CalendarHub::ICS::Parser.new(nil)
    events = parser.events

    assert_empty(events)
  end

  test "handles events without UID" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:No UID Event
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_empty(events)
  end

  test "handles events without DTSTART" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:no-start-time
      SUMMARY:No Start Time Event
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_empty(events)
  end

  test "handles all-day events with VALUE=DATE" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:all-day-event
      SUMMARY:All Day Event
      DTSTART;VALUE=DATE:20250101
      DTEND;VALUE=DATE:20250102
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "America/New_York")
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_predicate(event, :all_day)
    # All-day events should be in the specified timezone
    ny_zone = ActiveSupport::TimeZone["America/New_York"]

    assert_equal(ny_zone.local(2025, 1, 1, 0, 0, 0), event.starts_at)
    assert_equal(ny_zone.local(2025, 1, 2, 0, 0, 0), event.ends_at)
  end

  test "handles all-day events without T in date string" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:all-day-no-t
      SUMMARY:All Day No T
      DTSTART:20250101
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_predicate(event, :all_day)
    # Should default to 1 day duration for all-day events
    assert_equal(event.starts_at + 1.day, event.ends_at)
  end

  test "handles events with TZID parameter" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:tz-event
      SUMMARY:Timezone Event
      DTSTART;TZID=America/Los_Angeles:20250101T100000
      DTEND;TZID=America/Los_Angeles:20250101T110000
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("America/Los_Angeles", event.time_zone)
    refute_predicate(event, :all_day)
  end

  test "handles UTC events with Z suffix" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:utc-event
      SUMMARY:UTC Event
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    # UTC events with Z suffix should be parsed correctly
    refute_nil(event.starts_at)
    refute_nil(event.ends_at)
    assert_operator(event.ends_at, :>, event.starts_at)
  end

  test "handles folded lines" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:folded-event
      SUMMARY:This is a very long summary that gets folded
       across multiple lines in the ICS format
      DESCRIPTION:This is also a long description that
       spans multiple lines and should be properly
       unfolded by the parser
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    expected_summary = "This is a very long summary that gets foldedacross multiple lines in the ICS format"
    expected_description = "This is also a long description thatspans multiple lines and should be properlyunfolded by the parser"

    assert_equal(expected_summary, event.summary)
    assert_equal(expected_description, event.description)
  end

  test "handles lines without colon separator" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:test-event
      SUMMARY:Test Event
      INVALID-LINE-WITHOUT-COLON
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("test-event", event.uid)
  end

  test "handles escaped characters in values" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:escaped-event
      SUMMARY:Event with escaped\\nnewlines
      DESCRIPTION:Line 1\\nLine 2\\nLine 3
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("Event with escaped\nnewlines", event.summary)
    assert_equal("Line 1\nLine 2\nLine 3", event.description)
  end

  test "handles invalid datetime gracefully" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:invalid-datetime
      SUMMARY:Invalid DateTime Event
      DTSTART:invalid-date-string
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "America/New_York")
    events = parser.events

    # Invalid datetime should cause the event to be skipped
    assert_equal(0, events.count)
  end

  test "handles datetime with already normalized format" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:normalized-datetime
      SUMMARY:Normalized DateTime Event
      DTSTART:2025-01-01 10:00:00
      DTEND:2025-01-01 11:00:00
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    refute_nil(event.starts_at)
    refute_nil(event.ends_at)
  end

  test "handles unknown timezone gracefully" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:unknown-tz
      SUMMARY:Unknown Timezone Event
      DTSTART;TZID=Unknown/Timezone:20250101T100000
      DTEND;TZID=Unknown/Timezone:20250101T110000
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "America/New_York")
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    # Should fallback to default zone
    assert_equal("Unknown/Timezone", event.time_zone)
    refute_nil(event.starts_at)
  end

  test "handles events with default status" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:no-status
      SUMMARY:No Status Event
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("confirmed", event.status)
  end

  test "handles custom properties" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      UID:custom-props
      SUMMARY:Custom Properties Event
      DTSTART:20250101T100000Z
      DTEND:20250101T110000Z
      X-CUSTOM-PROP:custom value
      X-ANOTHER-PROP:another value
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = CalendarHub::ICS::Parser.new(ics_content)
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("custom value", event.raw_properties[:"x-custom-prop"])
    assert_equal("another value", event.raw_properties[:"x-another-prop"])
  end

  test "parse_line handles parameters without values" do
    parser = CalendarHub::ICS::Parser.new("")

    # Test parameter parsing with missing value after =
    key, params, value = parser.send(:parse_line, "DTSTART;TZID=:20250101T100000Z")

    assert_equal("DTSTART", key)
    assert_equal("", params["TZID"])
    assert_equal("20250101T100000Z", value)
  end

  test "parse_datetime handles date-only format without VALUE=DATE parameter" do
    parser = CalendarHub::ICS::Parser.new("", default_time_zone: "America/New_York")

    # Test date without T but without VALUE=DATE parameter
    result = parser.send(:parse_datetime, "20250101", {})

    refute_nil(result)
    assert_equal(2025, result.year)
    assert_equal(1, result.month)
    assert_equal(1, result.day)
  end

  test "parse_datetime handles TZID with valid timezone for all-day events" do
    parser = CalendarHub::ICS::Parser.new("", default_time_zone: "UTC")

    result = parser.send(:parse_datetime, "20250101", { "VALUE" => "DATE", "TZID" => "America/Los_Angeles" })

    refute_nil(result)
    assert_equal(2025, result.year)
    assert_equal(1, result.month)
    assert_equal(1, result.day)
  end

  test "parse_datetime handles TZID with valid timezone for timed events" do
    parser = CalendarHub::ICS::Parser.new("", default_time_zone: "UTC")

    result = parser.send(:parse_datetime, "20250101T100000", { "TZID" => "America/New_York" })

    refute_nil(result)
    # Should be parsed in Eastern time
    assert_equal("EST", result.zone)
  end

  test "default_zone falls back to UTC when invalid timezone" do
    parser = CalendarHub::ICS::Parser.new("", default_time_zone: "Invalid/Timezone")

    zone = parser.send(:default_zone)

    assert_equal("UTC", zone.name)
  end

  test "normalize_datetime_string handles date-only format" do
    parser = CalendarHub::ICS::Parser.new("")

    result = parser.send(:normalize_datetime_string, "20250101")

    assert_equal("2025-01-01", result)
  end

  test "parsed_components extracts date and time components correctly" do
    parser = CalendarHub::ICS::Parser.new("")

    result = parser.send(:parsed_components, "20250315", "143022")

    assert_equal(2025, result[:year])
    assert_equal(3, result[:month])
    assert_equal(15, result[:day])
    assert_equal(14, result[:hour])
    assert_equal(30, result[:minute])
    assert_equal(22, result[:second])
  end

  test "unfolded_lines handles content with no folded lines" do
    content = "LINE1\nLINE2\nLINE3"
    parser = CalendarHub::ICS::Parser.new(content)

    lines = parser.send(:unfolded_lines)

    assert_equal(["LINE1", "LINE2", "LINE3"], lines)
  end

  test "unfolded_lines handles content ending with folded line" do
    content = "LINE1\nLINE2\n FOLDED"
    parser = CalendarHub::ICS::Parser.new(content)

    lines = parser.send(:unfolded_lines)

    assert_equal(["LINE1", "LINE2FOLDED"], lines)
  end

  test "decode_value handles multiple escaped newlines" do
    parser = CalendarHub::ICS::Parser.new("")

    result = parser.send(:decode_value, "Line 1\\nLine 2\\nLine 3")

    assert_equal("Line 1\nLine 2\nLine 3", result)
  end

  test "all_day_event? returns true for VALUE=DATE parameter" do
    parser = CalendarHub::ICS::Parser.new("")

    attributes = { dtstart_params: { "VALUE" => "DATE" }, dtstart_raw: "20250101T100000Z" }

    assert(parser.send(:all_day_event?, attributes))
  end

  test "all_day_event? returns true for date without T even without VALUE=DATE" do
    parser = CalendarHub::ICS::Parser.new("")

    attributes = { dtstart_params: {}, dtstart_raw: "20250101" }

    assert(parser.send(:all_day_event?, attributes))
  end

  test "all_day_event? returns false for timed events" do
    parser = CalendarHub::ICS::Parser.new("")

    attributes = { dtstart_params: {}, dtstart_raw: "20250101T100000Z" }

    refute(parser.send(:all_day_event?, attributes))
  end

  test "all_day_event? handles missing dtstart_params and dtstart_raw" do
    parser = CalendarHub::ICS::Parser.new("")

    attributes = {}

    assert(parser.send(:all_day_event?, attributes)) # Empty dtstart_raw excludes "T", so it's considered all-day
  end
end
