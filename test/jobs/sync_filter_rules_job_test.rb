# frozen_string_literal: true

require "test_helper"

class SyncFilterRulesJobTest < ActiveJob::TestCase
  test "performs with filter_rule_id" do
    source = calendar_sources(:provider)
    filter_rule = FilterRule.create!(
      pattern: "Job Test",
      field_name: "title",
      match_type: "contains",
      calendar_source: source,
    )

    service_mock = mock
    service_mock.expects(:sync_filter_rules)
    CalendarHub::Sync::FilterSyncService.expects(:new).with(source: source).returns(service_mock)

    SyncFilterRulesJob.perform_now(filter_rule.id)
  end

  test "performs with calendar_source_id kwarg" do
    source = calendar_sources(:provider)

    service_mock = mock
    service_mock.expects(:sync_filter_rules)
    CalendarHub::Sync::FilterSyncService.expects(:new).with(source: source).returns(service_mock)

    SyncFilterRulesJob.perform_now(calendar_source_id: source.id)
  end

  test "performs with nil arguments fans out one job per active source" do
    active_source_count = CalendarSource.active.count

    assert_enqueued_jobs(active_source_count, only: SyncFilterRulesJob) do
      SyncFilterRulesJob.perform_now(calendar_source_id: nil)
    end
  end

  test "fan-out jobs each receive a calendar_source_id" do
    active_ids = CalendarSource.active.ids

    SyncFilterRulesJob.perform_now(calendar_source_id: nil)

    enqueued = queue_adapter.enqueued_jobs.select { |j| j["job_class"] == "SyncFilterRulesJob" }
    enqueued_source_ids = enqueued.map { |j| j["arguments"].last["calendar_source_id"] }

    assert_equal(active_ids.sort, enqueued_source_ids.sort)
  end

  test "handles RecordNotFound gracefully" do
    assert_nothing_raised do
      SyncFilterRulesJob.perform_now(99999)
    end
  end

  test "handles RecordNotFound for calendar_source_id gracefully" do
    assert_nothing_raised do
      SyncFilterRulesJob.perform_now(calendar_source_id: 99999)
    end
  end

  test "retry_on is configured for SQLite3::BusyException" do
    # Verify that the job class has retry_on configured for lock contention errors
    # so the queue framework handles retries instead of sleeping in-process
    rescue_handlers = SyncFilterRulesJob.rescue_handlers
    busy_handler = rescue_handlers.find { |h| h[0] == "SQLite3::BusyException" }
    timeout_handler = rescue_handlers.find { |h| h[0] == "ActiveRecord::StatementTimeout" }

    refute_nil(busy_handler, "SyncFilterRulesJob must have retry_on for SQLite3::BusyException")
    refute_nil(timeout_handler, "SyncFilterRulesJob must have retry_on for ActiveRecord::StatementTimeout")
  end

  test "FilterSyncService does not contain sleep calls for lock contention" do
    # Read the service source to verify sleep has been removed
    source_file = Rails.root.join("app/services/calendar_hub/sync/filter_sync_service.rb").read
    refute_match(/\bsleep\b/, source_file, "FilterSyncService should not call sleep for lock contention")
  end
end
