# frozen_string_literal: true

require "test_helper"

class CalendarSourcesControllerTest < ActionDispatch::IntegrationTest
  test "creates a calendar source" do
    params = {
      calendar_source: {
        name: "ICS Feed",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "shared-test",
        time_zone: "UTC",
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    assert_redirected_to calendar_events_path
  end

  test "schedules sync job" do
    source = calendar_sources(:jane_app)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
  end
end
