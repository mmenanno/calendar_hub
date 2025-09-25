# frozen_string_literal: true

require "test_helper"

class AutoSyncSchedulerJobTest < ActiveJob::TestCase
  setup do
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
end
