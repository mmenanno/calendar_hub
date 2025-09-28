# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class AutoSyncSchedulerTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup do
      CalendarSource.find_each { |source| source.update!(auto_sync_enabled: false) }

      @source1 = calendar_sources(:provider)
      @source2 = calendar_sources(:ics_feed)
      @source1.update!(auto_sync_enabled: true, sync_frequency_minutes: 30)
      @source2.update!(auto_sync_enabled: true, sync_frequency_minutes: 60)
    end

    test "finds sources that are due for sync" do
      @source1.update!(last_synced_at: 1.hour.ago)
      @source2.update!(last_synced_at: 30.minutes.ago)

      scheduler = ::CalendarHub::AutoSyncScheduler.new
      due_sources = scheduler.find_sources_due_for_sync

      assert_equal(1, due_sources.count)
      assert_equal(@source1, due_sources.first)
    end

    test "excludes sources not due for sync" do
      @source1.update!(last_synced_at: 10.minutes.ago)
      @source2.update!(last_synced_at: 15.minutes.ago)

      scheduler = ::CalendarHub::AutoSyncScheduler.new
      due_sources = scheduler.find_sources_due_for_sync

      assert_empty(due_sources)
    end

    test "excludes sources with auto sync disabled" do
      @source1.update!(auto_sync_enabled: false, last_synced_at: 1.hour.ago)
      @source2.update!(auto_sync_enabled: false, last_synced_at: 1.hour.ago)

      scheduler = ::CalendarHub::AutoSyncScheduler.new
      due_sources = scheduler.find_sources_due_for_sync

      assert_empty(due_sources)
    end

    test "excludes sources outside sync window" do
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
        scheduler = ::CalendarHub::AutoSyncScheduler.new
        due_sources = scheduler.find_sources_due_for_sync

        assert_empty(due_sources)
      end
    end

    test "excludes sources with running sync attempts" do
      @source1.update!(last_synced_at: 1.hour.ago)
      @source2.update!(last_synced_at: 1.hour.ago)
      @source1.sync_attempts.create!(status: :running)

      scheduler = ::CalendarHub::AutoSyncScheduler.new
      due_sources = scheduler.find_sources_due_for_sync

      assert_equal(1, due_sources.count)
      assert_equal(@source2, due_sources.first)
    end

    test "schedules sync jobs for due sources" do
      @source1.update!(last_synced_at: 1.hour.ago)
      @source2.update!(last_synced_at: 1.hour.ago)

      assert_enqueued_jobs(2, only: SyncCalendarJob) do
        scheduler = ::CalendarHub::AutoSyncScheduler.new
        result = scheduler.call

        assert_equal(2, result)
      end
    end

    test "returns zero when no sources are due" do
      @source1.update!(last_synced_at: 10.minutes.ago)
      @source2.update!(last_synced_at: 15.minutes.ago)

      scheduler = ::CalendarHub::AutoSyncScheduler.new
      result = scheduler.call

      assert_equal(0, result)
    end

    test "uses domain optimization for scheduling" do
      @source1.update!(
        ingestion_url: "https://example.com/calendar1.ics",
        last_synced_at: 1.hour.ago,
      )
      @source2.update!(
        ingestion_url: "https://example.com/calendar2.ics",
        last_synced_at: 1.hour.ago,
      )

      freeze_time do
        frozen_now = Time.current
        schedule = {
          @source1.id => frozen_now - 1.second,
          @source2.id => frozen_now + 10.minutes,
        }
        ::CalendarHub::DomainOptimizer.stubs(:optimize_sync_schedule).returns(schedule)

        scheduler = ::CalendarHub::AutoSyncScheduler.new
        result = scheduler.call

        assert_equal(2, result)
      end
    end
  end
end
