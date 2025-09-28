# frozen_string_literal: true

require "test_helper"

class AppleCalendarClientAllDayTest < ActiveSupport::TestCase
  include ICSTestHelpers

  setup do
    @client = AppleCalendar::Client.new(credentials: { username: "test", app_specific_password: "test" })
  end

  test "generates correct ICS for all-day event" do
    payload = build_apple_payload(
      uid: "test-all-day-123",
      summary: "All Day Event",
      description: "This is an all-day event",
      location: "Everywhere",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      all_day: true,
    )

    ics = @client.send(:build_ics, payload)

    assert_match(/DTSTART;VALUE=DATE:20250927/, ics)
    assert_match(/DTEND;VALUE=DATE:20250928/, ics)
    refute_match(/DTSTART:.*T.*Z/, ics, "All-day event should not have time component in DTSTART")
    refute_match(/DTEND:.*T.*Z/, ics, "All-day event should not have time component in DTEND")
  end

  test "generates correct ICS for timed event" do
    payload = {
      uid: "test-timed-456",
      summary: "Timed Event",
      description: "This is a timed event",
      location: "Office",
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 15, 0, 0),
      all_day: false,
    }

    ics = @client.send(:build_ics, payload)

    assert_match(/DTSTART:20250927T140000Z/, ics)
    assert_match(/DTEND:20250927T150000Z/, ics)
    refute_match(/VALUE=DATE/, ics, "Timed event should not have VALUE=DATE")
  end

  test "defaults to timed event when all_day is not specified" do
    payload = {
      uid: "test-default-789",
      summary: "Default Event",
      starts_at: Time.utc(2025, 9, 27, 10, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 11, 0, 0),
    }

    ics = @client.send(:build_ics, payload)

    assert_match(/DTSTART:20250927T100000Z/, ics)
    assert_match(/DTEND:20250927T110000Z/, ics)
    refute_match(/VALUE=DATE/, ics, "Default should be timed event")
  end
end
