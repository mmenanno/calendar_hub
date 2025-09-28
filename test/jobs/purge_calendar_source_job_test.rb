# frozen_string_literal: true

require "test_helper"

class PurgeCalendarSourceJobTest < ActiveSupport::TestCase
  test "purges archived source and related records" do
    source = calendar_sources(:ics_feed)
    # Create related rows
    event = CalendarEvent.create!(calendar_source: source, external_id: "e1", title: "t", starts_at: Time.current, ends_at: 1.hour.from_now)
    attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

    # Simulate archive (soft delete)
    source.soft_delete!

    # Run purge
    PurgeCalendarSourceJob.perform_now(source.id)

    assert_nil CalendarSource.unscoped.find_by(id: source.id)
    assert_nil CalendarEvent.find_by(id: event.id)
    assert_nil SyncAttempt.find_by(id: attempt.id)
  end

  test "handles non-existent source gracefully" do
    non_existent_id = 99999

    # Should not raise an error when source doesn't exist
    assert_nothing_raised do
      PurgeCalendarSourceJob.perform_now(non_existent_id)
    end
  end
end
