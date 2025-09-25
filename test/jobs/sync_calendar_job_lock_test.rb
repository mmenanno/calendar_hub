# frozen_string_literal: true

require "test_helper"

class SyncCalendarJobLockTest < ActiveSupport::TestCase
  test "back-to-back performs complete without error and finish attempts" do
    source = calendar_sources(:ics_feed)
    # Stub the service to a quick no-op to keep test fast
    CalendarHub::SyncService.any_instance.stubs(:call).returns([])

    assert_difference -> { SyncAttempt.where(calendar_source: source).count }, +2 do
      SyncCalendarJob.perform_now(source.id)
      SyncCalendarJob.perform_now(source.id)
    end

    last_two = SyncAttempt.where(calendar_source: source).order(created_at: :desc).limit(2)

    assert last_two.all?(&:success?)
  end
end
