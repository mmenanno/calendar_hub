# frozen_string_literal: true

require "test_helper"

class CleanupStaleSyncAttemptsJobTest < ActiveJob::TestCase
  setup do
    @source = calendar_sources(:provider)
  end

  test "marks stale queued attempts as failed" do
    stale_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 3.hours.ago,
    )

    CleanupStaleSyncAttemptsJob.perform_now

    stale_attempt.reload

    assert_equal("failed", stale_attempt.status)
    assert_includes(stale_attempt.message, "timed out")
  end

  test "marks stale running attempts as failed" do
    stale_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :running,
      created_at: 3.hours.ago,
      started_at: 3.hours.ago,
    )

    CleanupStaleSyncAttemptsJob.perform_now

    stale_attempt.reload

    assert_equal("failed", stale_attempt.status)
    assert_includes(stale_attempt.message, "timed out")
  end

  test "does not mark recent queued attempts as failed" do
    recent_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 30.minutes.ago,
    )

    CleanupStaleSyncAttemptsJob.perform_now

    recent_attempt.reload

    assert_equal("queued", recent_attempt.status)
  end

  test "does not mark completed attempts as failed" do
    completed_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      created_at: 3.hours.ago,
      finished_at: 3.hours.ago,
    )

    CleanupStaleSyncAttemptsJob.perform_now

    completed_attempt.reload

    assert_equal("success", completed_attempt.status)
  end

  test "respects custom threshold" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 90.minutes.ago,
    )

    # With default 2 hour threshold, this should not be marked as stale
    CleanupStaleSyncAttemptsJob.perform_now

    assert_equal("queued", attempt.reload.status)

    # With 1 hour threshold, this should be marked as stale
    CleanupStaleSyncAttemptsJob.perform_now(threshold: 1.hour)

    assert_equal("failed", attempt.reload.status)
  end

  test "handles multiple stale attempts" do
    3.times do
      SyncAttempt.create!(
        calendar_source: @source,
        status: :queued,
        created_at: 3.hours.ago,
      )
    end

    CleanupStaleSyncAttemptsJob.perform_now

    assert_equal(0, @source.sync_attempts.where(status: "queued").count)
    assert_equal(3, @source.sync_attempts.where(status: "failed").count)
  end

  test "does nothing when no stale attempts exist" do
    # Create only recent attempts
    SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 30.minutes.ago,
    )

    assert_nothing_raised do
      CleanupStaleSyncAttemptsJob.perform_now
    end
  end
end
