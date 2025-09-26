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
end
