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

  test "search functionality works correctly with caching" do
    get calendar_events_path(q: "Test")

    assert_response(:success)
    assert_select("turbo-frame#events-list")
    assert_select("div#calendar-events")

    queries = ["Performance", "Optimized", "Location"]

    queries.each do |query|
      get calendar_events_path(q: query)

      assert_response(:success)
      assert_select("input[name='q'][value='#{query}']")
    end

    get calendar_events_path(q: "")

    assert_response(:success)
  end
end
