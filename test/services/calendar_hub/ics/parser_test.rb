# frozen_string_literal: true

require "test_helper"

class ParserTest < ActiveSupport::TestCase
  test "parses jane app ics file" do
    parser = CalendarHub::ICS::Parser.new(file_fixture("jane_app.ics").read, default_time_zone: "America/Toronto")
    events = parser.events

    assert_equal 2, events.count

    first = events.first

    assert_equal "jane-123", first.uid
    assert_equal "Initial Consultation", first.summary
    assert_equal Time.find_zone!("America/Toronto").parse("2025-09-22 14:00"), first.starts_at
    assert_equal "confirmed", first.status
    assert_equal(
      {
        uid: "jane-123",
        summary: "Initial Consultation",
        description: "Consultation session with client",
        location: "Studio A",
        status: "confirmed",
        dtstamp: "20250920T150000Z",
        "x-janeapp-practitioner": "Dr. Smith",
        "x-janeapp-client": "John Doe",
        "x-janeapp-treatment": "Massage Therapy",
        "x-janeapp-notes": "Bring paperwork",
      },
      first.raw_properties.slice(:uid, :summary, :description, :location, :status, :dtstamp, :"x-janeapp-practitioner", :"x-janeapp-client", :"x-janeapp-treatment", :"x-janeapp-notes"),
    )

    second = events.second

    assert_equal "cancelled", second.status
  end
end
