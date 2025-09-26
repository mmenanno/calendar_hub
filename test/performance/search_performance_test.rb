# frozen_string_literal: true

require "test_helper"

class SearchPerformanceTest < ActionDispatch::IntegrationTest
  setup do
    @source = calendar_sources(:provider)

    10.times do |i|
      CalendarEvent.create!(
        calendar_source: @source,
        external_id: "perf-test-#{i}",
        title: "Performance Test Event #{i}",
        description: "Test event for performance testing",
        location: "Test Location #{i}",
        starts_at: (i + 1).days.from_now,
        ends_at: (i + 1).days.from_now + 1.hour,
        status: :confirmed,
        time_zone: "UTC",
      )
    end

    EventMapping.create!(
      calendar_source: @source,
      pattern: "Performance",
      replacement: "Optimized",
      match_type: "contains",
      active: true,
    )
  end

  test "search performance with caching" do
    get calendar_events_path(q: "Test")

    start_time = Time.current

    5.times do
      get calendar_events_path(q: "Performance")
      get calendar_events_path(q: "Optimized")
      get calendar_events_path(q: "Location")
    end

    end_time = Time.current
    duration = end_time - start_time

    assert_operator(duration, :<, 1.0, "Search should complete within 1 second with caching, took #{duration}s")

    assert_response(:success)
  end
end
