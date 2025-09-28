# frozen_string_literal: true

require "test_helper"

class AllDayParserTest < ActiveSupport::TestCase
  include ICSTestHelpers

  test "parses all-day event with VALUE=DATE parameter" do
    event_data = build_all_day_event(
      uid: "all-day-123",
      summary: "All Day Event",
      description: "This is an all-day event",
      starts_at: Date.parse("2025-09-27"),
      ends_at: Date.parse("2025-09-28"),
    )
    ics_content = build_ics_content(event_data)

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
    event_data = build_all_day_event(
      uid: "all-day-456",
      summary: "Another All Day Event",
      starts_at: Date.parse("2025-09-27"),
      ends_at: Date.parse("2025-09-28"),
    )
    ics_content = build_ics_content(event_data).gsub(";VALUE=DATE", "")

    parser = ::CalendarHub::ICS::Parser.new(ics_content, default_time_zone: "UTC")
    events = parser.events

    assert_equal(1, events.count)

    event = events.first

    assert_equal("all-day-456", event.uid)
    assert_equal("Another All Day Event", event.summary)
    assert(event.all_day, "Event should be marked as all-day")
  end

  test "parses timed event correctly" do
    event_data = build_simple_event(
      uid: "timed-789",
      summary: "Timed Event",
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 15, 0, 0),
    )
    ics_content = build_ics_content(event_data)

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
