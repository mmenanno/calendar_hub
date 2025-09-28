# frozen_string_literal: true

require "test_helper"

class CalendarEventTest < ActiveSupport::TestCase
  include ModelBuilders

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

  test "duration calculates correctly" do
    @event.starts_at = Time.zone.parse("2025-09-22 10:00")
    @event.ends_at = Time.zone.parse("2025-09-22 11:30")

    assert_equal(1.5.hours, @event.duration)
  end

  test "time_range returns correct range" do
    start_time = Time.zone.parse("2025-09-22 10:00")
    end_time = Time.zone.parse("2025-09-22 11:30")

    @event.starts_at = start_time
    @event.ends_at = end_time

    assert_equal(start_time..end_time, @event.time_range)
  end

  test "normalized_attributes returns correct hash" do
    @event.title = "Test Event"
    @event.description = "Test Description"
    @event.location = "Test Location"
    @event.status = "confirmed"
    @event.data = { "custom" => "data" }

    normalized = @event.normalized_attributes

    assert_equal("Test Event", normalized[:title])
    assert_equal("Test Description", normalized[:description])
    assert_equal("Test Location", normalized[:location])
    assert_equal("confirmed", normalized[:status])
    assert_equal({ "custom" => "data" }, normalized[:data])
    assert_kind_of(Time, normalized[:starts_at])
    assert_kind_of(Time, normalized[:ends_at])
  end

  test "all_day? returns correct boolean" do
    @event.all_day = true

    assert_predicate(@event, :all_day?)

    @event.all_day = false

    refute_predicate(@event, :all_day?)
  end

  test "duration_days calculates correctly for all-day events" do
    @event.all_day = true
    @event.starts_at = Time.zone.parse("2025-09-22 00:00")
    @event.ends_at = Time.zone.parse("2025-09-24 00:00")

    assert_equal(2, @event.duration_days)
  end

  test "duration_days returns 0 for non-all-day events" do
    @event.all_day = false
    @event.starts_at = Time.zone.parse("2025-09-22 10:00")
    @event.ends_at = Time.zone.parse("2025-09-24 11:00")

    assert_equal(0, @event.duration_days)
  end

  test "assigns default time_zone when blank" do
    @event.time_zone = nil
    @event.valid?

    assert_equal(@event.calendar_source.time_zone, @event.time_zone)
  end

  test "assigns UTC time_zone when source has no time_zone" do
    # Create a new calendar source without time_zone setting
    source_without_tz = CalendarSource.create!(
      name: "Test Source",
      calendar_identifier: "test-123",
      ingestion_url: "https://example.com/cal.ics",
    )

    event = CalendarEvent.new(
      calendar_source: source_without_tz,
      external_id: "test-event",
      title: "Test Event",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      all_day: false,
    )
    event.time_zone = nil
    event.valid?

    # Should default to AppSetting default or UTC
    expected_tz = AppSetting.instance.default_time_zone || "UTC"

    assert_equal(expected_tz, event.time_zone)
  end

  test "validates all_day times are at beginning of day" do
    @event.all_day = true
    @event.time_zone = "UTC"
    @event.starts_at = Time.zone.parse("2025-09-22 10:30:15") # Not beginning of day
    @event.ends_at = Time.zone.parse("2025-09-23 00:00:00")

    refute_predicate(@event, :valid?)
    assert_includes(@event.errors[:starts_at], "must be at beginning of day for all-day events")
  end

  test "validates all_day end times are at beginning of day" do
    @event.all_day = true
    @event.time_zone = "UTC"
    @event.starts_at = Time.zone.parse("2025-09-22 00:00:00")
    @event.ends_at = Time.zone.parse("2025-09-23 14:30:00") # Not beginning of day

    refute_predicate(@event, :valid?)
    assert_includes(@event.errors[:ends_at], "must be at beginning of day for all-day events")
  end

  test "allows valid all_day times" do
    @event.all_day = true
    @event.time_zone = "UTC"
    @event.starts_at = Time.zone.parse("2025-09-22 00:00:00")
    @event.ends_at = Time.zone.parse("2025-09-23 00:00:00")

    assert_predicate(@event, :valid?)
  end

  test "refresh_fingerprint handles nil values" do
    @event.title = nil
    @event.description = nil
    @event.location = nil
    @event.data = nil

    # Should not raise an error
    @event.send(:refresh_fingerprint)

    refute_nil(@event.fingerprint)
  end

  test "audit! handles rescue gracefully" do
    # Mock CalendarEventAudit.create! to raise an error
    CalendarEventAudit.stubs(:create!).raises(StandardError.new("Audit failed"))

    # Should log a warning but not raise an error
    Rails.logger.expects(:warn).with(includes("[Audit] Failed to record audit"))

    @event.send(:audit!, :created)
  end

  test "scopes work correctly" do
    future_event = calendar_events(:future_event)
    past_event = calendar_events(:past_event)

    upcoming_events = CalendarEvent.upcoming

    assert_includes(upcoming_events, future_event)
    refute_includes(upcoming_events, past_event)
  end

  test "needs_sync scope works correctly" do
    unsynced_event = calendar_events(:unsynced_event)
    outdated_event = calendar_events(:outdated_event)

    needs_sync_events = CalendarEvent.needs_sync

    assert_includes(needs_sync_events, unsynced_event)
    assert_includes(needs_sync_events, outdated_event)
  end

  test "ensure_end_after_start validation with nil values" do
    @event.starts_at = nil
    @event.ends_at = Time.current

    # Should not add error when starts_at is nil, but other validations may fail
    @event.valid?

    refute_includes(@event.errors[:ends_at], "must be after the start time")

    @event.starts_at = Time.current
    @event.ends_at = nil

    # Should not add error when ends_at is nil, but other validations may fail
    @event.valid?

    refute_includes(@event.errors[:ends_at], "must be after the start time")
  end

  test "ensure_all_day_times_are_valid with nil values" do
    @event.all_day = true
    @event.starts_at = nil
    @event.ends_at = Time.current

    # Should not validate when starts_at is nil
    @event.valid?

    refute_includes(@event.errors[:starts_at], "must be at beginning of day for all-day events")
  end

  test "refresh_fingerprint handles encoding issues" do
    # Set attributes with special characters that might cause encoding issues
    @event.title = "Café Meeting™"
    @event.description = "Naïve résumé"
    @event.location = "São Paulo"

    # Should not raise an error
    assert_nothing_raised do
      @event.send(:refresh_fingerprint)
    end

    refute_nil(@event.fingerprint)
  end

  test "refresh_fingerprint handles invalid UTF-8" do
    # Create strings with invalid UTF-8 sequences
    invalid_utf8 = "\xFF\xFE".dup.force_encoding("UTF-8")

    @event.title = invalid_utf8
    @event.description = invalid_utf8
    @event.location = invalid_utf8

    # Should handle invalid UTF-8 gracefully
    assert_nothing_raised do
      @event.send(:refresh_fingerprint)
    end

    refute_nil(@event.fingerprint)
  end

  test "broadcast methods are private" do
    # These methods are private, so we test they exist by checking if they're defined
    assert_includes(@event.private_methods, :broadcast_change)
    assert_includes(@event.private_methods, :broadcast_removal)
  end

  test "audit! with different verbs" do
    # Test audit with different action verbs
    ["created", "updated", "deleted"].each do |verb|
      # Mock the previous_changes to have some data
      @event.stubs(:previous_changes).returns({
        "title" => ["Old Title", "New Title"],
        "description" => [nil, "New Description"],
      })

      assert_nothing_raised do
        @event.send(:audit!, verb)
      end
    end
  end

  test "audit! handles complex change data" do
    # Mock previous_changes with various data types
    complex_changes = {
      "title" => ["Old Title", "New Title"],
      "starts_at" => [1.hour.ago, Time.current],
      "all_day" => [false, true],
      "data" => [{ "old" => "value" }, { "new" => "value" }],
    }

    @event.stubs(:previous_changes).returns(complex_changes)

    assert_nothing_raised do
      @event.send(:audit!, :updated)
    end

    # Verify audit record was created
    audit = CalendarEventAudit.last

    refute_nil(audit)
    assert_equal(@event, audit.calendar_event)
    assert_equal("updated", audit.action)
  end

  test "audit! handles non-array change values" do
    # Mock previous_changes with non-Array values to test the transform_values branches
    non_array_changes = {
      "title" => "Direct String Value",  # Not an array
      "status" => "confirmed",           # Not an array
      "normal_change" => ["old", "new"], # Normal array
    }

    @event.stubs(:previous_changes).returns(non_array_changes)

    assert_nothing_raised do
      @event.send(:audit!, :updated)
    end

    # Verify audit record was created with proper handling of non-array values
    audit = CalendarEventAudit.last

    refute_nil(audit)

    # For non-array values, both changes_from and changes_to should be the same value
    assert_equal("Direct String Value", audit.changes_from["title"])
    assert_equal("Direct String Value", audit.changes_to["title"])

    # For array values, should extract first and last
    assert_equal("old", audit.changes_from["normal_change"])
    assert_equal("new", audit.changes_to["normal_change"])
  end

  test "validates external_id uniqueness within calendar_source" do
    # Create another event with same external_id in different source
    other_source = CalendarSource.create!(
      name: "Other Source",
      calendar_identifier: "other-123",
      ingestion_url: "https://example.com/other.ics",
    )

    other_event = CalendarEvent.new(
      calendar_source: other_source,
      external_id: @event.external_id, # Same external_id
      title: "Other Event",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      time_zone: "UTC",
      all_day: false,
    )

    # Should be valid since it's in a different calendar_source
    assert_predicate(other_event, :valid?)

    # But same external_id in same source should be invalid
    duplicate_event = CalendarEvent.new(
      calendar_source: @event.calendar_source,
      external_id: @event.external_id,
      title: "Duplicate Event",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      time_zone: "UTC",
      all_day: false,
    )

    refute_predicate(duplicate_event, :valid?)
    assert_includes(duplicate_event.errors[:external_id], "has already been taken")
  end

  test "validates all_day inclusion" do
    @event.all_day = nil

    refute_predicate(@event, :valid?)
    assert_includes(@event.errors[:all_day], "is not included in the list")
  end

  test "validates required fields" do
    event = CalendarEvent.new(calendar_source: @event.calendar_source, all_day: false)

    refute_predicate(event, :valid?)
    assert_includes(event.errors[:external_id], "can't be blank")
    assert_includes(event.errors[:title], "can't be blank")
    assert_includes(event.errors[:starts_at], "can't be blank")
    assert_includes(event.errors[:ends_at], "can't be blank")
  end

  test "status enum works correctly" do
    @event.status = "confirmed"

    assert_equal("confirmed", @event.status)

    @event.status = "tentative"

    assert_equal("tentative", @event.status)

    @event.status = "cancelled"

    assert_equal("cancelled", @event.status)

    # Test invalid status
    assert_raises(ArgumentError) do
      @event.status = "invalid_status"
    end
  end

  test "callbacks are properly configured" do
    # Test that after_commit callbacks are set up by checking the callback chain
    create_callbacks = CalendarEvent._commit_callbacks.select { |cb| cb.kind == :after && cb.name == :commit }
    CalendarEvent._commit_callbacks.select { |cb| cb.kind == :after && cb.name == :commit }
    CalendarEvent._commit_callbacks.select { |cb| cb.kind == :after && cb.name == :commit }

    # Should have commit callbacks configured
    refute_empty(create_callbacks, "Should have commit callbacks configured")
  end
end
