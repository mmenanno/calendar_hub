# frozen_string_literal: true

require "test_helper"

class CalendarEventsControllerTest < ActionDispatch::IntegrationTest
  test "renders index" do
    get calendar_events_path

    assert_response :success
    assert_select "h2", text: "Upcoming Events"
  end

  test "filters by source" do
    source = calendar_sources(:ics_feed)
    get calendar_events_path, params: { source_id: source.id }

    assert_response :success
  end

  test "hides excluded events by default" do
    excluded_event = calendar_events(:provider_consult)
    # Update to future date so it shows in upcoming scope
    excluded_event.update!(
      sync_exempt: true,
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    get calendar_events_path

    assert_response(:success)
    refute_match(excluded_event.title, response.body)
  end

  test "shows excluded events when show_excluded is true" do
    excluded_event = calendar_events(:provider_consult)
    excluded_event.update!(
      sync_exempt: true,
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    get calendar_events_path(show_excluded: "true")

    assert_response(:success)
    assert_match(excluded_event.title, response.body)
    assert_match("Excluded", response.body)
  end

  test "shows toggle button for excluded events" do
    get calendar_events_path

    assert_response(:success)
    assert_match("Show Excluded", response.body)

    get calendar_events_path(show_excluded: "true")

    assert_response(:success)
    assert_match("Hide Excluded", response.body)
  end

  test "search includes mapped titles" do
    event = calendar_events(:provider_consult)
    event.update!(
      title: "Counselling Session",
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    EventMapping.create!(
      calendar_source: event.calendar_source,
      pattern: "Counselling",
      replacement: "Therapy",
      match_type: "contains",
      active: true,
    )

    get calendar_events_path(q: "Therapy")

    assert_response(:success)
    assert_match(event.title, response.body)

    get calendar_events_path(q: "Counselling")

    assert_response(:success)
    assert_match(event.title, response.body)
  end

  test "renders turbo frame partial for events-list frame request" do
    get calendar_events_path, headers: { "Turbo-Frame" => "events-list" }

    assert_response(:success)
    # Should render partial instead of full page
    refute_match("Upcoming Events", response.body) # H2 title not in partial
  end

  test "renders show action successfully" do
    event = calendar_events(:provider_consult)
    get calendar_event_path(event)

    assert_response(:success)
    assert_select "h1", text: /#{event.title}/
  end

  test "toggle_sync excludes event when currently included" do
    event = calendar_events(:provider_consult)
    event.update!(sync_exempt: false)

    patch toggle_sync_calendar_event_path(event)

    assert_response(:redirect)
    assert_redirected_to(calendar_event_path(event))
    assert_predicate(event.reload, :sync_exempt?)
    assert_match("excluded", flash[:notice])
  end

  test "toggle_sync includes event when currently excluded" do
    event = calendar_events(:provider_consult)
    event.update!(sync_exempt: true)

    patch toggle_sync_calendar_event_path(event)

    assert_response(:redirect)
    assert_redirected_to(calendar_event_path(event))
    refute_predicate(event.reload, :sync_exempt?)
    assert_match("included", flash[:notice])
  end

  test "toggle_sync with turbo_stream format returns streams" do
    event = calendar_events(:provider_consult)
    event.update!(sync_exempt: false)

    patch toggle_sync_calendar_event_path(event),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_equal("text/vnd.turbo-stream.html", response.media_type)
    assert_match("turbo-stream", response.body)
    assert_predicate(event.reload, :sync_exempt?)
  end

  test "search by location" do
    event = calendar_events(:provider_consult)
    event.update!(
      location: "Conference Room A",
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    get calendar_events_path(q: "Conference")

    assert_response(:success)
    assert_match(event.title, response.body)
  end

  test "search with blank term returns all events" do
    get calendar_events_path(q: "")

    assert_response(:success)
  end

  test "search with whitespace-only term returns all events" do
    get calendar_events_path(q: "   ")

    assert_response(:success)
  end

  test "search is case insensitive" do
    event = calendar_events(:provider_consult)
    event.update!(
      title: "Important Meeting",
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    get calendar_events_path(q: "IMPORTANT")

    assert_response(:success)
    assert_match(event.title, response.body)
  end

  test "event_search_data is cached" do
    # Temporarily enable caching for this test
    original_cache_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    event = calendar_events(:provider_consult)
    event.update!(
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    # First call should cache the data by triggering the search
    # Use a search term that will match the event
    get(calendar_events_path(q: "consultation"))

    assert_response(:success)

    # Verify cache key exists - the private method should have been called
    cache_key = "event_search_data/#{event.id}/#{event.reload.updated_at.to_i}"
    cached_data = Rails.cache.read(cache_key)

    refute_nil(cached_data, "Cache should contain search data after search request")
    assert_equal(event.title.downcase, cached_data[:original_title])
  ensure
    # Restore original cache store
    Rails.cache = original_cache_store
  end

  test "search handles events with nil location" do
    event = calendar_events(:provider_consult)
    event.update!(
      location: nil,
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    get calendar_events_path(q: "consultation")

    assert_response(:success)
    assert_match(event.title, response.body)
  end

  test "search handles events with minimal title gracefully" do
    event = calendar_events(:provider_consult)
    event.update!(
      title: "XYZ", # Minimal but unique valid title
      location: nil, # Test nil location handling too
      starts_at: 1.week.from_now,
      ends_at: 1.week.from_now + 1.hour,
    )

    # Search for something that won't match
    get(calendar_events_path(q: "nonexistent_search_term"))

    assert_response(:success)
    # Should not crash even with minimal data and no matches
    assert_match("No events found", response.body)

    # Search for the minimal title should work
    get(calendar_events_path(q: "XYZ"))

    assert_response(:success)
    assert_match(event.title, response.body)
    refute_match("No events found", response.body)
  end

  test "filter by invalid source_id returns no selected source" do
    get calendar_events_path, params: { source_id: 99999 }

    assert_response(:success)
    # Should handle gracefully when source not found
  end

  test "filter by empty source_id param" do
    get calendar_events_path, params: { source_id: "" }

    assert_response(:success)
    # Should handle gracefully when source_id is empty
  end
end
