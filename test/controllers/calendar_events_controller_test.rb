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
end
