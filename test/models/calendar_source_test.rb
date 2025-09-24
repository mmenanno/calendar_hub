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
end
