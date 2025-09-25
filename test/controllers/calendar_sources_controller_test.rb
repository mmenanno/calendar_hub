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
    source = calendar_sources(:provider)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
  end

  test "unarchives a calendar source" do
    archived_source = calendar_sources(:archived_source)

    assert_predicate archived_source.deleted_at, :present?
    refute_predicate archived_source, :active?

    patch unarchive_calendar_source_path(archived_source)

    archived_source.reload

    assert_nil archived_source.deleted_at
    assert_predicate archived_source, :active?
    assert_redirected_to calendar_events_path
  end

  test "unarchive with turbo stream" do
    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    archived_source.reload

    assert_nil archived_source.deleted_at
    assert_predicate archived_source, :active?
    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "unarchive handles non-existent source" do
    # In test environment, this should raise RecordNotFound
    # but we'll check if it gets to a 404 response instead

    patch(unarchive_calendar_source_path(99999))

    assert_response(:not_found)
  end

  test "unarchive works only on archived sources" do
    active_source = calendar_sources(:provider)

    # Should still work but not change anything since it's already active
    patch unarchive_calendar_source_path(active_source)

    active_source.reload

    assert_nil active_source.deleted_at
    assert_predicate active_source, :active?
    assert_redirected_to calendar_events_path
  end
end
