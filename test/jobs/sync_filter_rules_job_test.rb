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
      SyncFilterRulesJob.perform_now(99_999)
    end
  end

  test "handles RecordNotFound for calendar_source_id gracefully" do
    assert_nothing_raised do
      SyncFilterRulesJob.perform_now(calendar_source_id: 99_999)
    end
  end

  test "re-enqueues itself when the database is locked" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::FilterSyncService.any_instance.stubs(:sync_filter_rules).raises(ActiveRecord::StatementTimeout, "database is locked")

    assert_enqueued_with(job: SyncFilterRulesJob) do
      SyncFilterRulesJob.perform_now(calendar_source_id: source.id)
    end
  end

  test "FilterSyncService does not contain sleep calls for lock contention" do
    # Read the service source to verify sleep has been removed
    source_file = Rails.root.join("app/services/calendar_hub/sync/filter_sync_service.rb").read

    refute_match(/\bsleep\b/, source_file, "FilterSyncService should not call sleep for lock contention")
  end
end
