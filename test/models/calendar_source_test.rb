# frozen_string_literal: true

require "test_helper"

class CalendarSourceTest < ActiveSupport::TestCase
  include ModelBuilders

  test "within_sync_window? true when no window set" do
    s = CalendarSource.new(time_zone: "UTC")

    assert_predicate s, :within_sync_window?
  end

  test "within_sync_window? respects simple window" do
    s = CalendarSource.new(time_zone: "UTC", sync_window_start_hour: 9, sync_window_end_hour: 17)

    assert s.within_sync_window?(now: Time.utc(2025, 1, 1, 10, 0, 0))
    refute s.within_sync_window?(now: Time.utc(2025, 1, 1, 8, 0, 0))
  end

  test "within_sync_window? wraps midnight" do
    s = CalendarSource.new(time_zone: "UTC", sync_window_start_hour: 22, sync_window_end_hour: 2)

    assert s.within_sync_window?(now: Time.utc(2025, 1, 1, 23, 0, 0))
    assert s.within_sync_window?(now: Time.utc(2025, 1, 1, 1, 0, 0))
    refute s.within_sync_window?(now: Time.utc(2025, 1, 1, 15, 0, 0))
  end

  test "soft_delete! sets deleted_at and deactivates source" do
    source = calendar_sources(:provider)

    assert_predicate source, :active?
    assert_nil source.deleted_at

    source.soft_delete!

    refute_predicate source, :active?
    refute_nil source.deleted_at
    assert_kind_of Time, source.deleted_at
  end

  test "default scope excludes soft deleted sources" do
    active_count = CalendarSource.count
    archived_source = calendar_sources(:archived_source)

    # Archived source should not appear in default scope
    refute_includes CalendarSource.all, archived_source

    # But should appear in unscoped
    assert_includes CalendarSource.unscoped.all, archived_source

    # Active sources should still be included
    assert_equal active_count, CalendarSource.count
  end

  test "unarchiving restores source to active state" do
    archived_source = calendar_sources(:archived_source)

    refute_predicate archived_source, :active?
    refute_nil archived_source.deleted_at

    # Simulate unarchive action
    archived_source.update!(deleted_at: nil, active: true)

    assert_predicate archived_source, :active?
    assert_nil archived_source.deleted_at
  end

  test "archived source is not syncable" do
    archived_source = calendar_sources(:archived_source)

    refute_predicate archived_source, :syncable?
  end

  test "unarchived source becomes syncable" do
    archived_source = calendar_sources(:archived_source)
    archived_source.update!(deleted_at: nil, active: true)

    # Should be syncable if it has an ingestion adapter
    assert_predicate archived_source, :syncable?
  end

  test "time_zone defaults to AppSetting when not set" do
    source = CalendarSource.new
    source.settings = {}

    # Should fall back to AppSetting default or UTC
    expected_zone = AppSetting.instance.default_time_zone || "UTC"

    assert_equal(expected_zone, source.time_zone)
  end

  test "sync_frequency_minutes defaults to AppSetting when not set" do
    source = CalendarSource.new
    source.settings = {}

    expected_frequency = AppSetting.instance.default_sync_frequency_minutes

    assert_equal(expected_frequency, source.sync_frequency_minutes)
  end

  test "schedule_sync returns nil when not syncable" do
    source = CalendarSource.new(active: false)

    assert_nil(source.schedule_sync)
  end

  test "schedule_sync returns nil when sync already queued" do
    source = calendar_sources(:provider)
    build_sync_attempt(calendar_source: source, status: :queued)

    assert_nil(source.schedule_sync)
  end

  test "schedule_sync returns nil when sync already running" do
    source = calendar_sources(:provider)
    build_sync_attempt(calendar_source: source, status: :running)

    assert_nil(source.schedule_sync)
  end

  test "schedule_sync allows new sync when queued attempt is stale" do
    source = calendar_sources(:provider)
    # Create a stale queued attempt
    SyncAttempt.create!(
      calendar_source: source,
      status: :queued,
      created_at: 3.hours.ago,
    )

    # Should be able to schedule a new sync since the existing one is stale
    new_attempt = source.schedule_sync

    refute_nil(new_attempt)
    assert_equal("queued", new_attempt.status)
  end

  test "schedule_sync allows new sync when running attempt is stale" do
    source = calendar_sources(:provider)
    # Create a stale running attempt
    SyncAttempt.create!(
      calendar_source: source,
      status: :running,
      created_at: 3.hours.ago,
      started_at: 3.hours.ago,
    )

    # Should be able to schedule a new sync since the existing one is stale
    new_attempt = source.schedule_sync

    refute_nil(new_attempt)
    assert_equal("queued", new_attempt.status)
  end

  test "schedule_sync returns nil when outside sync window" do
    source = calendar_sources(:provider)
    source.update!(sync_window_start_hour: 9, sync_window_end_hour: 17, time_zone: "UTC")

    # Travel to time outside window (8 PM UTC)
    travel_to Time.utc(2025, 1, 1, 20, 0, 0) do
      # Verify we're outside the window first
      refute_predicate(source, :within_sync_window?)

      # Now test schedule_sync returns nil
      assert_nil(source.schedule_sync(force: false))
    end
  end

  test "schedule_sync works when forced" do
    source = calendar_sources(:provider)
    source.update!(sync_window_start_hour: 9, sync_window_end_hour: 17)

    # Force should work even outside window
    attempt = source.schedule_sync(force: true)

    refute_nil(attempt)
    assert_equal(source, attempt.calendar_source)
    assert_equal("queued", attempt.status)
  end

  test "syncable? requires active and ingestion_adapter" do
    source = calendar_sources(:provider)

    # Active with adapter should be syncable
    assert_predicate(source, :syncable?)

    # Inactive should not be syncable
    source.active = false

    refute_predicate(source, :syncable?)
  end

  test "auto_syncable? requires auto_sync_enabled and syncable" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: true)

    assert_predicate(source, :auto_syncable?)

    source.update!(auto_sync_enabled: false)

    refute_predicate(source, :auto_syncable?)
  end

  test "sync_due? returns false when not auto_syncable" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: false)

    refute_predicate(source, :sync_due?)
  end

  test "sync_due? returns true when never synced" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: true, last_synced_at: nil)

    assert_predicate(source, :sync_due?)
  end

  test "sync_due? respects sync frequency" do
    source = calendar_sources(:provider)
    source.update!(
      auto_sync_enabled: true,
      last_synced_at: 30.minutes.ago,
      sync_frequency_minutes: 60,
    )

    # Should not be due yet (30 min < 60 min)
    refute_predicate(source, :sync_due?)

    source.update!(last_synced_at: 90.minutes.ago)

    # Should be due now (90 min > 60 min)
    assert_predicate(source, :sync_due?)
  end

  test "next_auto_sync_time returns nil when not auto_syncable" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: false)

    assert_nil(source.next_auto_sync_time)
  end

  test "next_auto_sync_time handles never synced source" do
    source = calendar_sources(:provider)
    source.update!(auto_sync_enabled: true, last_synced_at: nil)

    travel_to Time.utc(2025, 1, 1, 12, 0, 0) do
      next_time = source.next_auto_sync_time

      # Should return current time when never synced and within window
      assert_in_delta(Time.current, next_time, 1.second)
    end
  end

  test "next_sync_time handles window wrapping midnight" do
    source = calendar_sources(:provider)
    source.update!(
      time_zone: "UTC",
      sync_window_start_hour: 22,
      sync_window_end_hour: 2,
    )

    # Test when current time is before start hour
    current_time = Time.utc(2025, 1, 1, 10, 0, 0) # 10 AM
    next_time = source.next_sync_time(now: current_time)

    # Should be today at 22:00
    expected = Time.utc(2025, 1, 1, 22, 0, 0)

    assert_equal(expected, next_time)
  end

  test "next_sync_time handles current day after end hour" do
    source = calendar_sources(:provider)
    source.update!(
      time_zone: "UTC",
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
    )

    # Test when current time is after end hour
    current_time = Time.utc(2025, 1, 1, 20, 0, 0) # 8 PM
    next_time = source.next_sync_time(now: current_time)

    # Should be tomorrow at 9:00
    expected = Time.utc(2025, 1, 2, 9, 0, 0)

    assert_equal(expected, next_time)
  end

  test "generate_change_hash includes mappings and settings" do
    source = calendar_sources(:provider)

    hash1 = source.generate_change_hash

    # Change sync frequency
    source.update!(sync_frequency_minutes: 120)
    hash2 = source.generate_change_hash

    refute_equal(hash1, hash2)
  end

  test "mark_synced! updates sync fields" do
    source = calendar_sources(:provider)
    token = "test-token-123"
    timestamp = Time.current

    source.mark_synced!(token: token, timestamp: timestamp)

    assert_equal(token, source.sync_token)
    assert_in_delta(timestamp, source.last_synced_at, 1.second)
    refute_nil(source.last_change_hash)
  end

  test "credentials encryption and decryption" do
    source = calendar_sources(:provider)
    test_credentials = { "username" => "test@example.com", "password" => "secret" }

    source.credentials = test_credentials
    source.save!

    source.reload
    decrypted = source.credentials

    assert_equal(test_credentials, decrypted)
  end

  test "set_import_start_date sets default on creation" do
    travel_to Time.zone.parse("2025-09-22 12:00") do
      source = calendar_sources(:test_source)
      new_source = CalendarSource.create!(source.attributes.except("id", "created_at", "updated_at", "import_start_date"))

      assert_in_delta(Time.current, new_source.import_start_date, 1.second)
    end
  end

  test "requires_ingestion_url? returns true" do
    source = CalendarSource.new

    assert(source.send(:requires_ingestion_url?))
  end

  test "validates presence of required fields" do
    source = CalendarSource.new

    refute_predicate(source, :valid?)
    assert_includes(source.errors[:name], "can't be blank")
    assert_includes(source.errors[:calendar_identifier], "can't be blank")
    assert_includes(source.errors[:ingestion_url], "can't be blank")
  end

  test "validates sync window hours" do
    source = CalendarSource.new(
      name: "Test",
      calendar_identifier: "test",
      ingestion_url: "https://example.com/cal.ics",
      sync_window_start_hour: 25, # Invalid
      sync_window_end_hour: -1,    # Invalid
    )

    refute_predicate(source, :valid?)
    assert_includes(source.errors[:sync_window_start_hour], "is not included in the list")
    assert_includes(source.errors[:sync_window_end_hour], "is not included in the list")
  end

  test "validates sync_frequency_minutes numericality" do
    source = CalendarSource.new(
      name: "Test",
      calendar_identifier: "test",
      ingestion_url: "https://example.com/cal.ics",
      sync_frequency_minutes: -10, # Invalid
    )

    refute_predicate(source, :valid?)
    assert_includes(source.errors[:sync_frequency_minutes], "must be greater than 0")
  end

  test "scopes work correctly" do
    active_source = calendar_sources(:provider)
    archived_source = calendar_sources(:archived_source)

    # Test active scope
    active_sources = CalendarSource.active

    assert_includes(active_sources, active_source)
    refute_includes(active_sources, archived_source)

    # Test auto_sync_enabled scope (need to set up data)
    active_source.update!(auto_sync_enabled: true)
    auto_sync_sources = CalendarSource.auto_sync_enabled

    assert_includes(auto_sync_sources, active_source)
  end

  test "schedule_sync_force returns attempt when sync attempts exist" do
    source = calendar_sources(:provider)
    existing_attempt = SyncAttempt.create!(calendar_source: source, status: :failed)

    # Even with existing failed attempt, force should create new one
    new_attempt = source.schedule_sync(force: true)

    refute_nil(new_attempt)
    refute_equal(existing_attempt.id, new_attempt.id)
  end

  test "sync_due handles edge case with exact frequency match" do
    source = calendar_sources(:provider)
    source.update!(
      auto_sync_enabled: true,
      last_synced_at: 60.minutes.ago,
      sync_frequency_minutes: 60,
    )

    # Should be due when exactly at frequency
    assert_predicate(source, :sync_due?)
  end

  test "next_auto_sync_time handles complex sync window scenarios" do
    source = calendar_sources(:provider)

    travel_to Time.utc(2025, 1, 1, 8, 0, 0) do # Before window
      source.update!(
        auto_sync_enabled: true,
        time_zone: "UTC",
        sync_window_start_hour: 9,
        sync_window_end_hour: 17,
        last_synced_at: 2.hours.ago,
        sync_frequency_minutes: 60,
      )

      next_time = source.next_auto_sync_time

      # Should be 9 AM on the current day since we're due and window opens at 9
      expected_time = Time.utc(2025, 1, 1, 9, 0, 0)

      assert_equal(expected_time, next_time)
    end
  end

  test "next_sync_time handles edge cases" do
    source = calendar_sources(:provider)

    # Test with no sync window restrictions
    source.update!(sync_window_start_hour: nil, sync_window_end_hour: nil)
    current_time = Time.utc(2025, 1, 1, 15, 0, 0)

    assert_equal(current_time, source.next_sync_time(now: current_time))
  end

  test "next_sync_time handles midnight wrapping edge cases" do
    source = calendar_sources(:provider)
    source.update!(
      time_zone: "UTC",
      sync_window_start_hour: 22,
      sync_window_end_hour: 2,
    )

    # Test when we're in the wrapped part (after midnight)
    travel_to Time.utc(2025, 1, 1, 1, 0, 0) do # 1 AM, within window
      next_time = source.next_sync_time

      # Should return current time since we're within window
      assert_in_delta(Time.current, next_time, 1.second)
    end

    # Test when we're between end and start (outside window)
    travel_to Time.utc(2025, 1, 1, 10, 0, 0) do # 10 AM, outside window
      next_time = source.next_sync_time

      # Should be today at 22:00
      expected = Time.utc(2025, 1, 1, 22, 0, 0)

      assert_equal(expected, next_time)
    end
  end

  test "next_sync_time handles same-day scheduling edge case" do
    source = calendar_sources(:provider)
    source.update!(
      time_zone: "UTC",
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
    )

    # Test when current hour is before start but after end from previous day
    travel_to Time.utc(2025, 1, 1, 8, 30, 0) do # 8:30 AM
      next_time = source.next_sync_time

      # Should be today at 9:00 AM
      expected = Time.utc(2025, 1, 1, 9, 0, 0)

      assert_equal(expected, next_time)
    end
  end

  test "next_sync_time handles complex conditional branches" do
    source = calendar_sources(:provider)
    source.update!(
      time_zone: "UTC",
      sync_window_start_hour: 9,
      sync_window_end_hour: 17,
    )

    # Test the specific branch where tz_now.hour > end_h || tz_now.hour >= start_h
    travel_to Time.utc(2025, 1, 1, 18, 0, 0) do # 6 PM - after end_h (17)
      next_time = source.next_sync_time

      # Should be tomorrow at 9:00 AM since we're past the end hour
      expected = Time.utc(2025, 1, 2, 9, 0, 0)

      assert_equal(expected, next_time)
    end

    # Test when tz_now.hour >= start_h during window
    travel_to Time.utc(2025, 1, 1, 15, 0, 0) do # 3 PM - within window
      next_time = source.next_sync_time

      # Should return current time since we're within window
      assert_in_delta(Time.current, next_time, 1.second)
    end
  end

  test "ingestion_adapter returns correct adapter" do
    source = calendar_sources(:provider)

    adapter = source.ingestion_adapter

    assert_kind_of(CalendarHub::Ingestion::GenericICSAdapter, adapter)
  end

  test "translator returns correct translator" do
    source = calendar_sources(:provider)

    translator = source.translator

    assert_kind_of(CalendarHub::Translators::EventTranslator, translator)
  end

  test "pending_events_count returns correct count" do
    source = calendar_sources(:provider)

    source.calendar_events.destroy_all

    # Create events with different sync states
    CalendarEvent.create!(
      calendar_source: source,
      external_id: "synced-event",
      title: "Synced Event",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      time_zone: "UTC",
      all_day: false,
      synced_at: Time.current,
      source_updated_at: 1.hour.ago, # Older than synced_at
    )

    CalendarEvent.create!(
      calendar_source: source,
      external_id: "pending-event",
      title: "Pending Event",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      time_zone: "UTC",
      all_day: false,
      synced_at: nil, # Never synced
      source_updated_at: Time.current,
    )

    assert_equal(1, source.pending_events_count)
  end

  test "encrypt_payload and decrypt_payload work correctly" do
    source = calendar_sources(:provider)
    test_data = { "key" => "value", "number" => 123 }

    encrypted = source.send(:encrypt_payload, test_data)

    refute_nil(encrypted)
    refute_equal(test_data.to_json, encrypted)

    decrypted = source.send(:decrypt_payload, encrypted)

    assert_equal(test_data, decrypted)
  end

  test "decrypt_payload handles nil input" do
    source = calendar_sources(:provider)

    result = source.send(:decrypt_payload, nil)
    # CalendarHub::CredentialEncryption.decrypt returns {} for nil input
    assert_empty(result)
  end
end
