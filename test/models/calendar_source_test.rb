# frozen_string_literal: true

require "test_helper"

class CalendarSourceTest < ActiveSupport::TestCase
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
end
