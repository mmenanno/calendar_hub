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

  test "performs with nil arguments syncs all active sources" do
    active_sources = CalendarSource.active.to_a

    active_sources.each do |source|
      service_mock = mock
      service_mock.expects(:sync_filter_rules)
      CalendarHub::Sync::FilterSyncService.expects(:new).with(source: source).returns(service_mock)
    end

    SyncFilterRulesJob.perform_now(calendar_source_id: nil)
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
end
