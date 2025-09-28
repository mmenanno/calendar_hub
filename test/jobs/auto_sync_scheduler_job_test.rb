# frozen_string_literal: true

require "test_helper"

class AutoSyncSchedulerJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    CalendarSource.find_each { |source| source.update!(auto_sync_enabled: false) }

    @source1 = calendar_sources(:provider)
    @source2 = calendar_sources(:ics_feed)
    @source1.update!(auto_sync_enabled: true, sync_frequency_minutes: 30)
    @source2.update!(auto_sync_enabled: true, sync_frequency_minutes: 60)
  end

  test "schedules sync for sources that are due" do
    @source1.update!(last_synced_at: 1.hour.ago)
    @source2.update!(last_synced_at: 30.minutes.ago)

    assert_enqueued_jobs(1, only: SyncCalendarJob) do
      AutoSyncSchedulerJob.perform_now
    end
  end

  test "skips sources not due for sync" do
    @source1.update!(last_synced_at: 10.minutes.ago)
    @source2.update!(last_synced_at: 15.minutes.ago)

    assert_no_enqueued_jobs(only: SyncCalendarJob) do
      AutoSyncSchedulerJob.perform_now
    end
  end

  test "skips sources with auto sync disabled" do
    @source1.update!(auto_sync_enabled: false, last_synced_at: 1.hour.ago)
    @source2.update!(auto_sync_enabled: false, last_synced_at: 1.hour.ago)

    result = AutoSyncSchedulerJob.perform_now

    assert_equal 0, result
  end

  test "skips sources outside sync window" do
    @source1.update!(
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
      last_synced_at: 1.hour.ago,
      settings: { time_zone: "UTC" },
    )
    @source2.update!(
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
      last_synced_at: 1.hour.ago,
      settings: { time_zone: "UTC" },
    )

    travel_to Time.current.change(hour: 20) do
      assert_no_enqueued_jobs(only: SyncCalendarJob) do
        AutoSyncSchedulerJob.perform_now
      end
    end
  end

  test "skips sources with running sync attempts" do
    @source1.update!(last_synced_at: 1.hour.ago)
    @source2.update!(last_synced_at: 1.hour.ago)
    @source1.sync_attempts.create!(status: :running)

    result = AutoSyncSchedulerJob.perform_now

    # Should only schedule @source2, not @source1
    assert_equal 1, result
  end

  test "optimizes scheduling by domain" do
    @source1.update!(
      ingestion_url: "https://one.example.com/calendar.ics",
      last_synced_at: 1.hour.ago,
    )
    @source2.update!(
      ingestion_url: "https://two.example.com/calendar.ics",
      last_synced_at: 1.hour.ago,
    )

    result = AutoSyncSchedulerJob.perform_now

    assert_equal 2, result
  end

  test "returns count of scheduled jobs" do
    @source1.update!(last_synced_at: 1.hour.ago)
    @source2.update!(last_synced_at: 1.hour.ago)

    result = AutoSyncSchedulerJob.perform_now

    assert_equal 2, result
  end

  test "schedules jobs immediately and with delay based on domain optimization" do
    # Create multiple sources from the same domain to trigger domain optimization staggering
    @source1.update!(
      ingestion_url: "https://example.com/calendar1.ics",
      last_synced_at: 1.hour.ago,
      auto_sync_enabled: true,
      sync_frequency_minutes: 30,
    )
    @source2.update!(
      ingestion_url: "https://example.com/calendar2.ics",
      last_synced_at: 1.hour.ago,
      auto_sync_enabled: true,
      sync_frequency_minutes: 30,
    )

    # Freeze time to ensure predictable behavior
    freeze_time do
      frozen_now = Time.current

      # Mock the domain optimizer to return a schedule with one immediate and one delayed time
      # The delayed time must be in the future relative to when the job captures 'now'
      schedule = {
        @source1.id => frozen_now - 1.second, # This will be <= now (immediate)
        @source2.id => frozen_now + 10.minutes, # This will be > now (delayed)
      }
      CalendarHub::DomainOptimizer.stubs(:optimize_sync_schedule).returns(schedule)

      result = AutoSyncSchedulerJob.perform_now

      assert_equal 2, result

      # Verify that jobs were scheduled (this covers the domain optimization code path)
      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job["job_class"] == "SyncCalendarJob" }

      assert_equal 2, enqueued_jobs.count
    end
  end
end
