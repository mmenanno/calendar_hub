# frozen_string_literal: true

require "test_helper"

class AllDayParserTest < ActiveSupport::TestCase
  test "parses all-day event with VALUE=DATE parameter" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:all-day-123
      DTSTAMP:20250926T120000Z
      DTSTART;VALUE=DATE:20250927
      DTEND;VALUE=DATE:20250928
      SUMMARY:All Day Event
      DESCRIPTION:This is an all-day event
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = ::CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "UTC")
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("all-day-123", event.uid)
    assert_equal("All Day Event", event.summary)
    assert(event.all_day, "Event should be marked as all-day")

    verify_all_day_times(event)
  end

  test "parses all-day event without VALUE=DATE parameter but date-only format" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:all-day-456
      DTSTAMP:20250926T120000Z
      DTSTART:20250927
      DTEND:20250928
      SUMMARY:Another All Day Event
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = ::CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "UTC")
    events = parser.events

    assert_equal(1, events.count)

    event = events.first

    assert_equal("all-day-456", event.uid)
    assert_equal("Another All Day Event", event.summary)
    assert(event.all_day, "Event should be marked as all-day")
  end

  test "parses timed event correctly" do
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//Test//EN
      BEGIN:VEVENT
      UID:timed-789
      DTSTAMP:20250926T120000Z
      DTSTART:20250927T140000Z
      DTEND:20250927T150000Z
      SUMMARY:Timed Event
      END:VEVENT
      END:VCALENDAR
    ICS

    parser = ::CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "UTC")
    events = parser.events

    assert_equal(1, events.count)
    event = events.first

    assert_equal("timed-789", event.uid)
    assert_equal("Timed Event", event.summary)
    refute(event.all_day, "Event should not be marked as all-day")

    verify_timed_event(event)
  end

  private

  def verify_all_day_times(event)
    start_time = event.starts_at.in_time_zone("UTC")
    end_time = event.ends_at.in_time_zone("UTC")

    assert_equal(0, start_time.hour)
    assert_equal(0, start_time.min)
    assert_equal(0, start_time.sec)
    assert_equal(0, end_time.hour)
    assert_equal(0, end_time.min)
    assert_equal(0, end_time.sec)
  end

  def verify_timed_event(event)
    duration_seconds = event.ends_at - event.starts_at

    assert_equal(3600, duration_seconds.to_i, "Event should be 1 hour long")

    start_time = event.starts_at.in_time_zone("UTC")

    refute_equal(0, start_time.hour, "Timed event should not start at beginning of day")
  end
end
