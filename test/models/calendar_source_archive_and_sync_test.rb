# frozen_string_literal: true

require "test_helper"

class CalendarSourceArchiveAndSyncTest < ActiveSupport::TestCase
  test "destroy via controller archives (soft-deletes) the source" do
    source = calendar_sources(:ics_feed)

    refute source.deleted_at
    source.soft_delete!

    refute_predicate source, :active?
    assert_predicate source.deleted_at, :present?
  end

  test "schedule_sync does not enqueue when queued attempt exists" do
    source = calendar_sources(:ics_feed)
    SyncAttempt.create!(calendar_source: source, status: :queued)

    assert_nil source.schedule_sync
  end
end
