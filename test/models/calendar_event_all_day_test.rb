# frozen_string_literal: true

require "test_helper"

class CalendarEventAllDayTest < ActiveSupport::TestCase
  setup do
    @source = calendar_sources(:ics_feed)
  end

  test "creates all-day event with valid times" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "all-day-test",
      title: "All Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    assert_predicate(event, :valid?, "All-day event with beginning-of-day times should be valid")
    assert(event.save!)
    assert_predicate(event, :all_day?)
  end

  test "validates all-day event start time must be beginning of day" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "invalid-all-day-start",
      title: "Invalid All Day Event",
      starts_at: Time.utc(2025, 9, 27, 14, 30, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    refute_predicate(event, :valid?)
    assert_includes(event.errors[:starts_at], "must be at beginning of day for all-day events")
  end

  test "validates all-day event end time must be beginning of day" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "invalid-all-day-end",
      title: "Invalid All Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 23, 59, 59),
      time_zone: "UTC",
      all_day: true,
    )

    refute_predicate(event, :valid?)
    assert_includes(event.errors[:ends_at], "must be at beginning of day for all-day events")
  end

  test "calculates duration_days correctly for single-day all-day event" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "single-day",
      title: "Single Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    assert_equal(1, event.duration_days)
  end

  test "calculates duration_days correctly for multi-day all-day event" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "multi-day",
      title: "Multi Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 30, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    assert_equal(3, event.duration_days)
  end

  test "timed event is not all-day" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "timed-event",
      title: "Timed Event",
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 15, 0, 0),
      time_zone: "UTC",
      all_day: false,
    )

    assert_predicate(event, :valid?)
    refute_predicate(event, :all_day?)
    assert_equal(0, event.duration_days)
  end

  test "all_day validation requires boolean value" do
    event = CalendarEvent.new(
      calendar_source: @source,
      external_id: "nil-all-day",
      title: "Nil All Day",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      time_zone: "UTC",
      all_day: nil,
    )

    refute_predicate(event, :valid?)
    assert_includes(event.errors[:all_day], "is not included in the list")
  end
end
