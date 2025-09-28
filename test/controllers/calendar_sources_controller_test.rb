# frozen_string_literal: true

require "test_helper"

class CalendarSourcesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include TurboStreamHelpers

  # INDEX ACTION TESTS
  test "index displays active and archived sources" do
    get calendar_sources_path

    assert_response :success
    assert_select "body" # Basic page structure

    # Should include active sources
    assert_includes response.body, calendar_sources(:provider).name
    assert_includes response.body, calendar_sources(:ics_feed).name

    # Should include archived sources section
    assert_includes response.body, calendar_sources(:archived_source).name
  end

  # SHOW ACTION TESTS
  test "show displays calendar source" do
    source = calendar_sources(:provider)
    get calendar_source_path(source)

    assert_response :success
    assert_includes response.body, source.name
  end

  # NEW ACTION TESTS
  test "new displays form for new calendar source" do
    get new_calendar_source_path

    assert_response :success
    assert_select "form"
  end

  # EDIT ACTION TESTS
  test "edit displays form for existing calendar source" do
    source = calendar_sources(:provider)
    get edit_calendar_source_path(source)

    assert_response :success
    assert_select "form"
    assert_includes response.body, source.name
  end

  # CREATE ACTION TESTS
  test "creates a calendar source with HTML format" do
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
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.created"), response.body
  end

  test "creates a calendar source with turbo stream format" do
    params = {
      calendar_source: {
        name: "Turbo Stream Feed",
        ingestion_url: "https://example.com/turbo.ics",
        calendar_identifier: "turbo-test",
        time_zone: "UTC",
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path,
        params: params,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "prepend", response.body
    assert_match "sources-list", response.body
    assert_match "toast-anchor", response.body
  end

  test "create handles validation errors with HTML format" do
    params = {
      calendar_source: {
        name: "", # Invalid - name is required
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "test",
      },
    }

    assert_no_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "create handles validation errors with turbo stream format" do
    params = {
      calendar_source: {
        name: "", # Invalid - name is required
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "test",
      },
    }

    assert_no_difference("CalendarSource.count") do
      post calendar_sources_path,
        params: params,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :unprocessable_entity
    assert_match "turbo-stream", response.body
    assert_match "replace", response.body
    assert_match "new_source_form", response.body
  end

  test "create applies credentials" do
    params = {
      calendar_source: {
        name: "Authenticated Feed",
        ingestion_url: "https://example.com/auth.ics",
        calendar_identifier: "auth-test",
        time_zone: "UTC",
        credentials: {
          http_basic_username: "testuser",
          http_basic_password: "testpass",
        },
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last

    assert_equal "testuser", source.credentials["http_basic_username"]
    assert_equal "testpass", source.credentials["http_basic_password"]
  end

  test "create converts blank sync_frequency_minutes to nil" do
    params = {
      calendar_source: {
        name: "Test Source",
        ingestion_url: "https://example.com/test.ics",
        calendar_identifier: "test",
        sync_frequency_minutes: "", # Blank should become nil
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last

    assert_nil source.read_attribute(:sync_frequency_minutes)
  end

  test "create preserves non-blank sync_frequency_minutes" do
    params = {
      calendar_source: {
        name: "Test Source",
        ingestion_url: "https://example.com/test.ics",
        calendar_identifier: "test",
        sync_frequency_minutes: "120", # Non-blank should be preserved
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last

    assert_equal 120, source.read_attribute(:sync_frequency_minutes)
  end

  # UPDATE ACTION TESTS
  test "updates calendar source with HTML format" do
    source = calendar_sources(:provider)
    params = {
      calendar_source: {
        name: "Updated Name",
        time_zone: "America/New_York",
      },
    }

    patch calendar_source_path(source), params: params

    assert_redirected_to calendar_events_path(source_id: source.id)
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.updated"), response.body

    source.reload

    assert_equal "Updated Name", source.name
    assert_equal "America/New_York", source.time_zone
  end

  test "updates calendar source with turbo stream format" do
    source = calendar_sources(:provider)
    params = {
      calendar_source: {
        name: "Turbo Updated Name",
      },
    }

    patch calendar_source_path(source),
      params: params,
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "update", response.body
    assert_match "modal", response.body
    assert_match "replace", response.body
    assert_match "toast-anchor", response.body

    source.reload

    assert_equal "Turbo Updated Name", source.name
  end

  test "update handles validation errors" do
    source = calendar_sources(:provider)
    params = {
      calendar_source: {
        name: "", # Invalid - name is required
      },
    }

    patch calendar_source_path(source), params: params

    assert_response :unprocessable_entity
    assert_select "form"

    source.reload

    refute_equal "", source.name # Name should not have changed
  end

  test "update applies credentials and preserves existing password when blank" do
    source = calendar_sources(:provider)
    source.update!(credentials: { http_basic_username: "olduser", http_basic_password: "oldpass" })

    params = {
      calendar_source: {
        name: "Updated with Creds",
        credentials: {
          http_basic_username: "newuser",
          http_basic_password: "", # Blank should preserve existing
        },
      },
    }

    patch calendar_source_path(source), params: params

    source.reload

    assert_equal "newuser", source.credentials["http_basic_username"]
    assert_equal "oldpass", source.credentials["http_basic_password"] # Should be preserved
  end

  # DESTROY ACTION TESTS
  test "destroys calendar source with HTML format" do
    source = calendar_sources(:provider)

    assert_nil source.deleted_at

    delete calendar_source_path(source)

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.archived"), response.body

    source.reload

    refute_nil source.deleted_at
    refute_predicate source, :active?
  end

  test "destroys calendar source with turbo stream format" do
    source = calendar_sources(:provider)

    delete calendar_source_path(source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "remove", response.body
    assert_match "replace", response.body
    assert_match "archived-sources-section", response.body
    assert_match "toast-anchor", response.body

    source.reload

    refute_nil source.deleted_at
  end

  # PURGE ACTION TESTS
  test "purge schedules purge job with HTML format" do
    archived_source = calendar_sources(:archived_source)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: PurgeCalendarSourceJob do
      delete purge_calendar_source_path(archived_source)
    end

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.purge_scheduled"), response.body
  end

  test "purge schedules purge job with turbo stream format" do
    archived_source = calendar_sources(:archived_source)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: PurgeCalendarSourceJob do
      delete purge_calendar_source_path(archived_source),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "remove", response.body
    assert_match "toast-anchor", response.body
  end

  test "purge removes archived sources section when no more archived sources" do
    # Create scenario where this is the last archived source
    CalendarSource.unscoped.where.not(deleted_at: nil).where.not(id: calendar_sources(:archived_source).id).destroy_all
    archived_source = calendar_sources(:archived_source)

    delete purge_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "remove", response.body
    assert_match "archived-sources", response.body
  end

  # SYNC_ALL ACTION TESTS
  test "sync_all schedules sync for all active sources" do
    CalendarSource.find_each { |source| source.update!(active: true, sync_window_start_hour: nil, sync_window_end_hour: nil) }
    SyncAttempt.where(status: ["queued", "running"]).destroy_all

    active_count = CalendarSource.active.count

    assert_enqueued_jobs(active_count, only: SyncCalendarJob) do
      post sync_all_calendar_sources_path
    end

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_scheduled", count: active_count), response.body
  end

  test "sync_all handles no syncable sources" do
    CalendarSource.find_each { |source| source.update!(active: false) }

    assert_no_enqueued_jobs(only: SyncCalendarJob) do
      post sync_all_calendar_sources_path
    end

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_skipped"), response.body
  end

  # SYNC ACTION TESTS
  test "sync schedules sync job for active source with HTML format" do
    source = calendar_sources(:provider)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_scheduled", count: 1), response.body
  end

  test "sync schedules sync job with turbo stream format" do
    source = calendar_sources(:provider)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post sync_calendar_source_path(source),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "replace", response.body
    assert_match "sync_status_source_#{source.id}", response.body
  end

  test "sync handles inactive source with HTML format" do
    source = calendar_sources(:provider)
    source.update!(active: false)
    clear_enqueued_jobs

    assert_enqueued_jobs 0 do
      post sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_inactive"), response.body
  end

  test "sync handles inactive source with turbo stream format" do
    source = calendar_sources(:provider)
    source.update!(active: false)
    clear_enqueued_jobs

    assert_enqueued_jobs 0 do
      post sync_calendar_source_path(source),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :unprocessable_entity
  end

  test "sync prevents double queueing" do
    source = calendar_sources(:provider)
    # Create a queued sync attempt
    source.sync_attempts.create!(status: :queued)
    clear_enqueued_jobs

    assert_enqueued_jobs 0 do
      post sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_inactive"), response.body
  end

  # FORCE_SYNC ACTION TESTS
  test "force_sync schedules sync job even when outside sync window" do
    source = calendar_sources(:provider)
    # Set a restrictive sync window that we're outside of
    source.update!(sync_window_start_hour: 2, sync_window_end_hour: 3)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post force_sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
  end

  test "force_sync with turbo stream format" do
    source = calendar_sources(:provider)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SyncCalendarJob do
      post force_sync_calendar_source_path(source),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "replace", response.body
    assert_match "sync_status_source_#{source.id}", response.body
  end

  test "force_sync handles inactive source" do
    source = calendar_sources(:provider)
    source.update!(active: false)
    clear_enqueued_jobs

    assert_enqueued_jobs 0 do
      post force_sync_calendar_source_path(source)
    end

    assert_redirected_to calendar_events_path(source_id: source.id)
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.sync_inactive"), response.body
  end

  # CHECK_DESTINATION ACTION TESTS
  test "check_destination succeeds when destination is found" do
    source = calendar_sources(:provider)

    # Mock the AppleCalendar::Client to return success
    mock_client = mock("client")
    mock_client.expects(:send).with(:discover_calendar_url, source.calendar_identifier).returns("https://example.com/calendar/path")
    AppleCalendar::Client.expects(:new).returns(mock_client)

    get check_destination_calendar_source_path(source)

    assert_redirected_to calendar_sources_path
    follow_redirect!
    # Check for the actual message structure in the response
    assert_match "Apple Calendar reachable", response.body
    assert_match "/calendar/path", response.body
  end

  test "check_destination handles errors" do
    source = calendar_sources(:provider)

    # Mock the AppleCalendar::Client to raise an error
    mock_client = mock("client")
    mock_client.expects(:send).raises(StandardError.new("Connection failed"))
    AppleCalendar::Client.expects(:new).returns(mock_client)

    get check_destination_calendar_source_path(source)

    assert_redirected_to calendar_sources_path
    follow_redirect!

    assert_match "Apple Calendar problem", response.body
    assert_match "Connection failed", response.body
  end

  # TOGGLE_ACTIVE ACTION TESTS
  test "toggle_active activates inactive source with HTML format" do
    source = calendar_sources(:provider)
    source.update!(active: false)

    patch toggle_active_calendar_source_path(source)

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.status_updated"), response.body

    source.reload

    assert_predicate source, :active?
  end

  test "toggle_active deactivates active source with HTML format" do
    source = calendar_sources(:provider)

    assert_predicate source, :active?

    patch toggle_active_calendar_source_path(source)

    source.reload

    refute_predicate source, :active?
  end

  test "toggle_active with turbo stream format" do
    source = calendar_sources(:provider)
    original_active = source.active?

    patch toggle_active_calendar_source_path(source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "replace", response.body
    assert_match "toast-anchor", response.body

    source.reload

    assert_equal !original_active, source.active?
  end

  # TOGGLE_AUTO_SYNC ACTION TESTS
  test "toggle_auto_sync enables auto sync with HTML format" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: false)

    patch toggle_auto_sync_calendar_source_path(source)

    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.auto_sync_updated"), response.body

    source.reload

    assert_predicate source, :auto_sync_enabled?
  end

  test "toggle_auto_sync disables auto sync with HTML format" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: true)

    patch toggle_auto_sync_calendar_source_path(source)

    source.reload

    refute_predicate source, :auto_sync_enabled?
  end

  test "toggle_auto_sync with turbo stream format" do
    source = calendar_sources(:provider)
    original_auto_sync = source.auto_sync_enabled?

    patch toggle_auto_sync_calendar_source_path(source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "replace", response.body
    assert_match "toast-anchor", response.body

    source.reload

    assert_equal !original_auto_sync, source.auto_sync_enabled?
  end

  # UNARCHIVE ACTION TESTS (expanded from existing)
  test "unarchives a calendar source" do
    archived_source = calendar_sources(:archived_source)

    assert_predicate archived_source.deleted_at, :present?
    refute_predicate archived_source, :active?

    patch unarchive_calendar_source_path(archived_source)

    archived_source.reload

    assert_nil archived_source.deleted_at
    assert_predicate archived_source, :active?
    assert_redirected_to calendar_events_path
    follow_redirect!

    assert_match I18n.t("flashes.calendar_sources.unarchived"), response.body
  end

  test "unarchive with turbo stream updates source status" do
    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    archived_source.reload

    assert_nil archived_source.deleted_at
    assert_predicate archived_source, :active?
    assert_response :success
  end

  test "unarchive with turbo stream returns correct response format" do
    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "remove", response.body
    assert_match "prepend", response.body
    assert_match "sources-list", response.body
    assert_match "toast-anchor", response.body
  end

  test "unarchive removes archived section when no more archived sources" do
    # Make this the only archived source
    CalendarSource.unscoped.where.not(deleted_at: nil).where.not(id: calendar_sources(:archived_source).id).destroy_all
    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "remove", response.body
    assert_match "archived-sources", response.body
  end

  test "unarchive handles non-existent source" do
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

  # PRIVATE METHOD TESTS (via integration)
  test "set_calendar_source uses unscoped for purge and unarchive actions" do
    archived_source = calendar_sources(:archived_source)

    # These actions should work with archived sources
    patch unarchive_calendar_source_path(archived_source)

    assert_response :redirect

    archived_source.update!(deleted_at: Time.current) # Re-archive

    delete purge_calendar_source_path(archived_source)

    assert_response :redirect
  end

  test "apply_credentials handles missing credentials parameter" do
    params = {
      calendar_source: {
        name: "No Creds Source",
        ingestion_url: "https://example.com/nocreds.ics",
        calendar_identifier: "nocreds",
      },
      # No credentials parameter
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last
    # Credentials will be an empty hash when no credentials are provided
    assert_empty(source.credentials)
  end

  test "apply_credentials strips whitespace and removes blank values" do
    params = {
      calendar_source: {
        name: "Whitespace Test",
        ingestion_url: "https://example.com/test.ics",
        calendar_identifier: "whitespace",
        credentials: {
          http_basic_username: "  testuser  ",
          http_basic_password: "   ", # Should be removed as blank
        },
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last

    assert_equal "testuser", source.credentials["http_basic_username"]
    assert_nil source.credentials["http_basic_password"]
  end

  test "apply_credentials handles all blank credentials" do
    params = {
      calendar_source: {
        name: "All Blank Creds",
        ingestion_url: "https://example.com/test.ics",
        calendar_identifier: "allblank",
        credentials: {
          http_basic_username: "   ",  # Should be removed as blank
          http_basic_password: "   ",  # Should be removed as blank
        },
      },
    }

    assert_difference("CalendarSource.count") do
      post calendar_sources_path, params: params
    end

    source = CalendarSource.last
    # When all credentials are blank, credentials should be empty
    assert_empty(source.credentials)
  end

  test "apply_credentials merges with existing credentials" do
    source = calendar_sources(:provider)
    source.update!(credentials: { existing_key: "existing_value", http_basic_username: "olduser" })

    params = {
      calendar_source: {
        name: "Updated",
        credentials: {
          http_basic_username: "newuser",
          http_basic_password: "newpass",
        },
      },
    }

    patch calendar_source_path(source), params: params

    source.reload
    credentials = source.credentials

    assert_equal "existing_value", credentials["existing_key"]  # Preserved
    assert_equal "newuser", credentials["http_basic_username"]  # Updated
    assert_equal "newpass", credentials["http_basic_password"]  # Added
  end
end
