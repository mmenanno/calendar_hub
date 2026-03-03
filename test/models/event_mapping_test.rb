# frozen_string_literal: true

require "test_helper"

class EventMappingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "create with source enqueues SyncCalendarJob" do
    source = calendar_sources(:provider)

    assert_enqueued_with(job: SyncCalendarJob) do
      EventMapping.create!(
        calendar_source: source,
        match_type: "contains",
        pattern: "Test",
        replacement: "Replaced",
      )
    end
  end

  test "create global mapping enqueues sync for active sources" do
    assert_enqueued_jobs(0, only: SyncCalendarJob)

    EventMapping.create!(
      match_type: "contains",
      pattern: "Global Test",
      replacement: "Global Replaced",
    )

    # Multiple SyncCalendarJobs should be enqueued (one per schedulable active source)
    assert_operator(enqueued_jobs_count(only: SyncCalendarJob), :>, 1)
  end

  private

  def enqueued_jobs_count(only:)
    queue_adapter = ActiveJob::Base.queue_adapter
    queue_adapter.enqueued_jobs.count { |job| job["job_class"] == only.name }
  end

  test "update with substantive change enqueues sync" do
    mapping = event_mappings(:basic_mapping)

    assert_enqueued_with(job: SyncCalendarJob) do
      mapping.update!(pattern: "Updated Pattern")
    end
  end

  test "position-only update does not enqueue sync" do
    mapping = event_mappings(:basic_mapping)

    assert_no_enqueued_jobs(only: SyncCalendarJob) do
      mapping.update!(position: 99)
    end
  end

  test "destroy enqueues sync" do
    mapping = event_mappings(:basic_mapping)

    assert_enqueued_with(job: SyncCalendarJob) do
      mapping.destroy!
    end
  end

  test "active toggle enqueues sync" do
    mapping = event_mappings(:basic_mapping)

    assert_enqueued_with(job: SyncCalendarJob) do
      mapping.update!(active: !mapping.active?)
    end
  end

  # Destination override

  test "has_destination_override? returns false when target_calendar_identifier is blank" do
    mapping = EventMapping.create!(
      match_type: "contains",
      pattern: "Test",
      replacement: "Replaced",
    )

    refute_predicate(mapping, :has_destination_override?)
  end

  test "has_destination_override? returns true when target_calendar_identifier is present" do
    mapping = EventMapping.create!(
      match_type: "contains",
      pattern: "Test",
      target_calendar_identifier: "Work",
    )

    assert_predicate(mapping, :has_destination_override?)
  end

  test "replacement is optional when target_calendar_identifier is present" do
    mapping = EventMapping.new(
      match_type: "contains",
      pattern: "Route Only",
      target_calendar_identifier: "Personal",
    )

    assert_predicate(mapping, :valid?)
  end

  test "must have replacement or destination calendar override" do
    mapping = EventMapping.new(
      match_type: "contains",
      pattern: "Nothing",
      replacement: "",
      target_calendar_identifier: "",
    )

    refute_predicate(mapping, :valid?)
    assert(mapping.errors[:base].any? { |e| e.include?("must have a replacement or a destination") })
  end

  test "valid with both replacement and destination override" do
    mapping = EventMapping.new(
      match_type: "contains",
      pattern: "Both",
      replacement: "Renamed",
      target_calendar_identifier: "Work",
    )

    assert_predicate(mapping, :valid?)
  end

  test "inactive source does not enqueue sync" do
    source = calendar_sources(:inactive_source)

    assert_no_enqueued_jobs(only: SyncCalendarJob) do
      EventMapping.create!(
        calendar_source: source,
        match_type: "contains",
        pattern: "Inactive Test",
        replacement: "Replaced",
      )
    end
  end
end
