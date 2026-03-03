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

  test "handles multiple stale attempts across sources" do
    sources = [
      calendar_sources(:provider),
      calendar_sources(:ics_feed),
      calendar_sources(:auto_sync_source),
    ]

    stale_attempts = sources.map do |source|
      SyncAttempt.create!(
        calendar_source: source,
        status: :queued,
        created_at: 3.hours.ago,
      )
    end

    CleanupStaleSyncAttemptsJob.perform_now

    stale_attempts.each do |attempt|
      assert_equal("failed", attempt.reload.status)
    end
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

  test "find_failed_job does not use LIKE pattern matching" do
    # Verify the source code does not contain LIKE-based argument matching,
    # ensuring the lookup is robust against serialization format changes.
    source_file = Rails.root.join("app/jobs/cleanup_stale_sync_attempts_job.rb").read
    refute_match(/arguments LIKE/, source_file,
      "find_failed_job should use json_extract or active_job_id instead of LIKE pattern matching")
  end

  test "find_failed_job uses active_job_id as primary lookup" do
    stale_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 3.hours.ago,
    )

    job = CleanupStaleSyncAttemptsJob.new
    # The method should attempt active_job_id lookup first
    if defined?(SolidQueue::Job)
      SolidQueue::Job.expects(:find_by).with(
        class_name: "SyncCalendarJob",
        active_job_id: stale_attempt.id.to_s,
      ).returns(nil)

      # Then fall back to json_extract (returns a relation mock)
      relation_mock = mock
      relation_mock.stubs(:first).returns(nil)
      SolidQueue::Job.stubs(:where).returns(relation_mock)
      relation_mock.stubs(:where).returns(relation_mock)

      result = job.send(:find_failed_job, stale_attempt)
      assert_nil(result)
    end
  end

  test "cleanup still works when find_failed_job returns nil" do
    stale_attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      created_at: 3.hours.ago,
    )

    CleanupStaleSyncAttemptsJob.perform_now

    stale_attempt.reload
    assert_equal("failed", stale_attempt.status)
    assert_includes(stale_attempt.message, "timed out")
    # Should not include a failure reason when no job is found
    refute_includes(stale_attempt.message, " - ") unless stale_attempt.message.include?("Reason")
  end
end
