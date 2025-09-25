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
end
