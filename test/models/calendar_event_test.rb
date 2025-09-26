# frozen_string_literal: true

require "test_helper"

class CalendarEventTest < ActiveSupport::TestCase
  setup do
    @event = calendar_events(:provider_consult)
  end

  test "valid fixture" do
    assert_predicate @event, :valid?
  end

  test "requires ends_at after starts_at" do
    @event.ends_at = @event.starts_at - 1.hour

    refute_predicate @event, :valid?
    assert_includes @event.errors[:ends_at], "must be after the start time"
  end

  test "defaults time_zone from source" do
    @event.time_zone = nil
    @event.valid?

    assert_equal @event.calendar_source.time_zone, @event.time_zone
  end

  test "fingerprint updates when content changes" do
    original_fingerprint = @event.fingerprint
    @event.update!(title: "Updated Title")

    refute_equal original_fingerprint, @event.reload.fingerprint
  end

  test "mark_synced sets timestamp" do
    travel_to Time.zone.parse("2025-09-22 12:00") do
      @event.mark_synced!

      assert_in_delta Time.zone.parse("2025-09-22 12:00"), @event.reload.synced_at, 1.second
    end
  end

  test "can access soft-deleted calendar source" do
    # Soft delete the calendar source
    @event.calendar_source.soft_delete!

    # Reload the event to clear any cached associations
    @event.reload

    # Should still be able to access the soft-deleted source
    refute_nil(@event.calendar_source)
    refute_nil(@event.calendar_source.deleted_at)
  end
end
