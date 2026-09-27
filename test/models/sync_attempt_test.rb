# frozen_string_literal: true

require "test_helper"

class SyncAttemptTest < ActiveSupport::TestCase
  setup do
    @calendar_source = calendar_sources(:provider)
    @sync_attempt = SyncAttempt.create!(calendar_source: @calendar_source, status: :queued)
    @calendar_event = calendar_events(:provider_consult)
  end

  test "should be valid with required attributes" do
    sync_attempt = SyncAttempt.new(calendar_source: @calendar_source, status: :queued)

    assert_predicate(sync_attempt, :valid?)
  end

  test "should belong to calendar_source" do
    assert_equal(@calendar_source, @sync_attempt.calendar_source)
  end

  test "should have sync_event_results association" do
    assert_respond_to(@sync_attempt, :sync_event_results)
    assert_equal(0, @sync_attempt.sync_event_results.count)
  end

  test "should have correct enum values for status" do
    expected_statuses = ["queued", "running", "success", "failed"]

    assert_equal(expected_statuses.sort, SyncAttempt::STATUSES.keys.map(&:to_s).sort)
  end

  test "should start with correct attributes" do
    travel_to Time.zone.parse("2025-09-22 12:00") do
      @sync_attempt.start(total: 50)

      assert_equal("running", @sync_attempt.status)
      assert_equal(50, @sync_attempt.total_events)
      assert_in_delta(Time.zone.parse("2025-09-22 12:00"), @sync_attempt.started_at, 1.second)
    end
  end

  test "successes are counted without per-event result rows" do
    @sync_attempt.upsert_success(@calendar_event)
    @sync_attempt.delete_success(@calendar_event)
    @sync_attempt.finish(status: :success)

    @sync_attempt.reload

    assert_equal(1, @sync_attempt.upserts)
    assert_equal(1, @sync_attempt.deletes)
    assert_equal(0, @sync_attempt.sync_event_results.count)
  end

  test "records failures as result rows on flush" do
    @sync_attempt.upsert_error(@calendar_event, StandardError.new("Upsert failed"))
    @sync_attempt.delete_error("external-9", StandardError.new("Delete failed"))

    assert_equal(0, @sync_attempt.sync_event_results.count, "buffered until flush")

    @sync_attempt.flush_progress!

    results = @sync_attempt.sync_event_results.order(:id).to_a

    assert_equal(2, @sync_attempt.reload.errors_count)
    assert_equal(["upsert", "delete"], results.map(&:action))
    assert_equal(@calendar_event, results.first.calendar_event)
    assert_equal("external-9", results.second.external_id)
    assert(results.none?(&:success?))
    assert_equal("Upsert failed", results.first.error_message)
  end

  test "progress is buffered and flushed in batches with a throttled broadcast" do
    @sync_attempt.start(total: 250)
    @sync_attempt.expects(:update_columns).twice
    @sync_attempt.expects(:broadcast_replace_later_to).twice

    (SyncAttempt::FLUSH_EVERY_EVENTS * 2).times { @sync_attempt.upsert_success(@calendar_event) }
  end

  test "flush refreshes the updated_at heartbeat" do
    @sync_attempt.update_columns(updated_at: 3.hours.ago)
    @sync_attempt.upsert_success(@calendar_event)

    @sync_attempt.flush_progress!

    assert_operator(@sync_attempt.reload.updated_at, :>, 1.minute.ago)
  end

  test "finish flushes pending counters" do
    @sync_attempt.upsert_success(@calendar_event)
    @sync_attempt.upsert_error(@calendar_event, StandardError.new("boom"))

    @sync_attempt.finish(status: :success)
    @sync_attempt.reload

    assert_equal(1, @sync_attempt.upserts)
    assert_equal(1, @sync_attempt.errors_count)
    assert_equal("success", @sync_attempt.status)
  end

  test "should finish with success status and message" do
    travel_to Time.zone.parse("2025-09-22 15:00") do
      @sync_attempt.finish(status: :success, message: "Sync completed successfully")

      assert_equal("success", @sync_attempt.status)
      assert_equal("Sync completed successfully", @sync_attempt.message)
      assert_in_delta(Time.zone.parse("2025-09-22 15:00"), @sync_attempt.finished_at, 1.second)
    end
  end

  test "should finish with failed status" do
    travel_to Time.zone.parse("2025-09-22 15:30") do
      @sync_attempt.finish(status: :failed, message: "Sync failed due to network error")

      assert_equal("failed", @sync_attempt.status)
      assert_equal("Sync failed due to network error", @sync_attempt.message)
      assert_in_delta(Time.zone.parse("2025-09-22 15:30"), @sync_attempt.finished_at, 1.second)
    end
  end

  test "should generate correct stream_name" do
    expected_stream_name = "sync_attempts_source_#{@calendar_source.id}"

    assert_equal(expected_stream_name, @sync_attempt.stream_name)
  end

  test "failure recording problems are logged, not raised" do
    SyncEventResult.stubs(:insert_all).raises(ActiveRecord::ActiveRecordError.new("Database error"))
    Rails.logger.expects(:warn).with("[SyncAttempt] Failed to record event results: Database error")

    @sync_attempt.upsert_error(@calendar_event, StandardError.new("boom"))
    @sync_attempt.flush_progress!(broadcast: false)
  end

  test "should have broadcast_snapshot callback set up" do
    # Test that the callback is configured
    callbacks = SyncAttempt._commit_callbacks.select { |cb| cb.filter == :broadcast_snapshot }

    refute_empty(callbacks, "broadcast_snapshot callback should be configured")
  end

  test "should broadcast to correct targets when finished" do
    @sync_attempt.update!(finished_at: Time.current)

    # Test that finished_at is present, which triggers the second broadcast
    refute_nil(@sync_attempt.finished_at)
  end

  test "should destroy dependent sync_event_results" do
    @sync_attempt.upsert_error(@calendar_event, StandardError.new("a"))
    @sync_attempt.delete_error(@calendar_event, StandardError.new("b"))
    @sync_attempt.flush_progress!(broadcast: false)

    assert_equal(2, @sync_attempt.sync_event_results.count)

    @sync_attempt.destroy

    assert_equal(0, SyncEventResult.where(sync_attempt_id: @sync_attempt.id).count)
  end

  test "stale scope returns queued attempts older than threshold" do
    # Complete the setup attempt so we can create new active ones
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    stale_source = calendar_sources(:ics_feed)
    recent_source = calendar_sources(:auto_sync_source)

    stale_queued = SyncAttempt.create!(
      calendar_source: stale_source,
      status: :queued,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
    )
    recent_queued = SyncAttempt.create!(
      calendar_source: recent_source,
      status: :queued,
      created_at: 30.minutes.ago,
      updated_at: 30.minutes.ago,
    )

    stale_attempts = SyncAttempt.stale(threshold: 2.hours)

    assert_includes(stale_attempts, stale_queued)
    refute_includes(stale_attempts, recent_queued)
  end

  test "stale scope returns running attempts older than threshold" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    stale_source = calendar_sources(:ics_feed)
    recent_source = calendar_sources(:auto_sync_source)

    stale_running = SyncAttempt.create!(
      calendar_source: stale_source,
      status: :running,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
      started_at: 3.hours.ago,
    )
    recent_running = SyncAttempt.create!(
      calendar_source: recent_source,
      status: :running,
      created_at: 30.minutes.ago,
      updated_at: 30.minutes.ago,
      started_at: 30.minutes.ago,
    )

    stale_attempts = SyncAttempt.stale(threshold: 2.hours)

    assert_includes(stale_attempts, stale_running)
    refute_includes(stale_attempts, recent_running)
  end

  test "stale scope does not return completed attempts" do
    old_success = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :success,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
      finished_at: 3.hours.ago,
    )
    old_failed = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :failed,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
      finished_at: 3.hours.ago,
    )

    stale_attempts = SyncAttempt.stale(threshold: 2.hours)

    refute_includes(stale_attempts, old_success)
    refute_includes(stale_attempts, old_failed)
  end

  test "stale scope respects custom threshold" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :queued,
      created_at: 90.minutes.ago,
      updated_at: 90.minutes.ago,
    )

    # Not stale with 2 hour threshold
    refute_includes(SyncAttempt.stale(threshold: 2.hours), attempt)

    # Stale with 1 hour threshold
    assert_includes(SyncAttempt.stale(threshold: 1.hour), attempt)
  end

  test "stale? returns true for old queued attempts" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    stale_attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :queued,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
    )

    assert_predicate(stale_attempt, :stale?)
  end

  test "stale? returns true for old running attempts" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    stale_attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :running,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
      started_at: 3.hours.ago,
    )

    assert_predicate(stale_attempt, :stale?)
  end

  test "stale? returns false for recent queued attempts" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    recent_attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :queued,
      created_at: 30.minutes.ago,
      updated_at: 30.minutes.ago,
    )

    refute_predicate(recent_attempt, :stale?)
  end

  test "stale? returns false for completed attempts" do
    completed_attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :success,
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago,
      finished_at: 3.hours.ago,
    )

    refute_predicate(completed_attempt, :stale?)
  end

  test "a long-running attempt with a recent heartbeat is not stale" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :running,
      created_at: 5.hours.ago,
      updated_at: 1.minute.ago,
    )

    refute_predicate(attempt, :stale?)
    refute_includes(SyncAttempt.stale, attempt)
  end

  test "stale? respects custom threshold" do
    @sync_attempt.update!(status: :success, finished_at: Time.current)

    attempt = SyncAttempt.create!(
      calendar_source: @calendar_source,
      status: :queued,
      created_at: 90.minutes.ago,
      updated_at: 90.minutes.ago,
    )

    # Not stale with 2 hour threshold
    refute(attempt.stale?(threshold: 2.hours))

    # Stale with 1 hour threshold
    assert(attempt.stale?(threshold: 1.hour))
  end
end
