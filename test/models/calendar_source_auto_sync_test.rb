# frozen_string_literal: true

require "test_helper"

class CalendarSourceAutoSyncTest < ActiveSupport::TestCase
  setup do
    @source = calendar_sources(:provider)
    @app_setting = AppSetting.instance
    @app_setting.update!(default_sync_frequency_minutes: 60)
  end

  test "sync_frequency_minutes returns source value when set" do
    @source.update!(sync_frequency_minutes: 30)

    assert_equal(30, @source.sync_frequency_minutes)
  end

  test "sync_frequency_minutes returns default when source value is nil" do
    @source.update!(sync_frequency_minutes: nil)

    assert_equal(60, @source.sync_frequency_minutes)
  end

  test "auto_syncable returns true when enabled and syncable" do
    @source.update!(auto_sync_enabled: true, active: true)

    assert_predicate(@source, :auto_syncable?)
  end

  test "auto_syncable returns false when disabled" do
    @source.update!(auto_sync_enabled: false, active: true)

    refute_predicate(@source, :auto_syncable?)
  end

  test "auto_syncable returns false when not syncable" do
    @source.update!(auto_sync_enabled: true, active: false)

    refute_predicate(@source, :auto_syncable?)
  end

  test "sync_due returns true when never synced" do
    @source.update!(last_synced_at: nil, auto_sync_enabled: true)

    assert_predicate(@source, :sync_due?)
  end

  test "sync_due returns true when last sync is older than frequency" do
    @source.update!(
      last_synced_at: 2.hours.ago,
      sync_frequency_minutes: 60,
      auto_sync_enabled: true,
    )

    assert_predicate(@source, :sync_due?)
  end

  test "sync_due returns false when last sync is newer than frequency" do
    @source.update!(
      last_synced_at: 30.minutes.ago,
      sync_frequency_minutes: 60,
      auto_sync_enabled: true,
    )

    refute_predicate(@source, :sync_due?)
  end

  test "sync_due returns false when auto sync disabled" do
    @source.update!(
      last_synced_at: 2.hours.ago,
      auto_sync_enabled: false,
    )

    refute_predicate(@source, :sync_due?)
  end

  test "next_auto_sync_time returns nil when not auto syncable" do
    @source.update!(auto_sync_enabled: false)

    assert_nil(@source.next_auto_sync_time)
  end

  test "next_auto_sync_time returns now when within window and due" do
    @source.update!(
      last_synced_at: 2.hours.ago,
      sync_frequency_minutes: 60,
      sync_window_start_hour: nil,
      sync_window_end_hour: nil,
      auto_sync_enabled: true,
    )

    assert_in_delta(Time.current, @source.next_auto_sync_time, 1.second)
  end

  test "next_auto_sync_time respects sync windows" do
    @source.update!(
      last_synced_at: 2.hours.ago,
      sync_frequency_minutes: 60,
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
      auto_sync_enabled: true,
      settings: { time_zone: "UTC" },
    )

    travel_to Time.current.change(hour: 20) do
      # At 20:00, outside sync window, should return next sync window start
      refute_predicate(@source, :within_sync_window?, "Should be outside sync window at 20:00")

      next_sync = @source.next_auto_sync_time

      # Should return the next available sync window time
      assert_operator(next_sync, :>, Time.current, "Next sync should be in the future when outside sync window")
    end
  end

  test "generate_change_hash includes mappings and settings" do
    @source.event_mappings.create!(pattern: "test", replacement: "new", position: 1)
    @source.update!(sync_frequency_minutes: 30)

    hash1 = @source.generate_change_hash

    refute_nil(hash1)

    @source.update!(sync_frequency_minutes: 60)
    hash2 = @source.generate_change_hash

    refute_equal(hash1, hash2)
  end

  test "mark_synced! updates change hash" do
    old_hash = @source.last_change_hash

    @source.mark_synced!(token: "test123")

    refute_equal(old_hash, @source.last_change_hash)
    assert_equal("test123", @source.sync_token)
    assert_in_delta(Time.current, @source.last_synced_at, 1.second)
  end

  test "scope auto_sync_enabled filters correctly" do
    @source.update!(auto_sync_enabled: true)
    source2 = CalendarSource.create!(
      name: "Test 2",
      ingestion_url: "https://example.com/test2.ics",
      calendar_identifier: "test2",
      auto_sync_enabled: false,
    )

    enabled_sources = CalendarSource.auto_sync_enabled

    assert_includes(enabled_sources, @source)
    refute_includes(enabled_sources, source2)
  end

  test "backs off exponentially after failed syncs instead of refetching every tick" do
    @source.update!(auto_sync_enabled: true, active: true, sync_frequency_minutes: 30, last_synced_at: 1.day.ago, consecutive_sync_failures: 3)
    @source.sync_attempts.create!(status: :failed, finished_at: 3.hours.ago, started_at: 3.hours.ago)

    # 30 min * 2**3 = 4 hours since the last attempt
    refute_predicate(@source, :sync_due?)
    assert(@source.sync_due?(now: 70.minutes.from_now))
    assert_equal(4.hours, @source.sync_backoff_interval)
  end

  test "backoff is capped at 24 hours" do
    @source.update!(sync_frequency_minutes: 600, consecutive_sync_failures: 10)

    assert_equal(24.hours, @source.sync_backoff_interval)
  end

  test "no backoff when the last sync completed with only per-event errors" do
    @source.update!(auto_sync_enabled: true, active: true, sync_frequency_minutes: 30, last_synced_at: 40.minutes.ago, consecutive_sync_failures: 2)
    @source.sync_attempts.create!(status: :success, errors_count: 1, finished_at: 40.minutes.ago)

    assert_predicate(@source, :sync_due?)
  end
end
