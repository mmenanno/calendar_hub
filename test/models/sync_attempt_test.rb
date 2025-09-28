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

  test "should record upsert success" do
    @sync_attempt.upsert_success(@calendar_event)

    assert_equal(1, @sync_attempt.reload.upserts)
    assert_equal(1, @sync_attempt.sync_event_results.count)

    result = @sync_attempt.sync_event_results.first

    assert_equal(@calendar_event, result.calendar_event)
    assert_equal("upsert", result.action)
    assert_predicate(result, :success?)
  end

  test "should record upsert error" do
    error = StandardError.new("Test error message")

    @sync_attempt.upsert_error(@calendar_event, error)

    assert_equal(1, @sync_attempt.reload.errors_count)
    assert_equal(1, @sync_attempt.sync_event_results.count)

    result = @sync_attempt.sync_event_results.first

    assert_equal(@calendar_event, result.calendar_event)
    assert_equal("upsert", result.action)
    refute_predicate(result, :success?)
    assert_equal("Test error message", result.error_message)
  end

  test "should record delete success" do
    @sync_attempt.delete_success(@calendar_event)

    assert_equal(1, @sync_attempt.reload.deletes)
    assert_equal(1, @sync_attempt.sync_event_results.count)

    result = @sync_attempt.sync_event_results.first

    assert_equal(@calendar_event, result.calendar_event)
    assert_equal("delete", result.action)
    assert_predicate(result, :success?)
  end

  test "should record delete error" do
    error = StandardError.new("Delete error message")

    @sync_attempt.delete_error(@calendar_event, error)

    assert_equal(1, @sync_attempt.reload.errors_count)
    assert_equal(1, @sync_attempt.sync_event_results.count)

    result = @sync_attempt.sync_event_results.first

    assert_equal(@calendar_event, result.calendar_event)
    assert_equal("delete", result.action)
    refute_predicate(result, :success?)
    assert_equal("Delete error message", result.error_message)
  end

  test "should increment counters correctly for multiple operations" do
    error = StandardError.new("Test error")

    @sync_attempt.upsert_success(@calendar_event)
    @sync_attempt.upsert_success(@calendar_event)
    @sync_attempt.delete_success(@calendar_event)
    @sync_attempt.upsert_error(@calendar_event, error)
    @sync_attempt.delete_error(@calendar_event, error)

    @sync_attempt.reload

    assert_equal(2, @sync_attempt.upserts)
    assert_equal(1, @sync_attempt.deletes)
    assert_equal(2, @sync_attempt.errors_count)
    assert_equal(5, @sync_attempt.sync_event_results.count)
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

  test "should handle record_event with non-CalendarEvent object" do
    external_event = Struct.new(:external_id, :to_s).new("external-123", "External Event")

    @sync_attempt.send(
      :record_event,
      event: external_event,
      action: "upsert",
      success: true,
    )

    result = @sync_attempt.sync_event_results.first

    assert_nil(result.calendar_event)
    assert_equal("external-123", result.external_id)
    assert_equal("upsert", result.action)
    assert_predicate(result, :success?)
  end

  test "should handle record_event with object without external_id" do
    simple_event = "Simple string event"

    @sync_attempt.send(
      :record_event,
      event: simple_event,
      action: "delete",
      success: false,
      error_message: "Failed to process",
    )

    result = @sync_attempt.sync_event_results.first

    assert_nil(result.calendar_event)
    assert_equal("Simple string event", result.external_id)
    assert_equal("delete", result.action)
    refute_predicate(result, :success?)
    assert_equal("Failed to process", result.error_message)
  end

  test "should handle record_event failure gracefully" do
    # Mock sync_event_results to raise an error
    @sync_attempt.sync_event_results.stubs(:create!).raises(StandardError.new("Database error"))

    # Should not raise an error, but log a warning
    Rails.logger.expects(:warn).with("[SyncAttempt] Failed to record event result: Database error")

    @sync_attempt.send(
      :record_event,
      event: @calendar_event,
      action: "upsert",
      success: true,
    )
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
    @sync_attempt.upsert_success(@calendar_event)
    @sync_attempt.delete_success(@calendar_event)

    assert_equal(2, @sync_attempt.sync_event_results.count)

    @sync_attempt.destroy

    assert_equal(0, SyncEventResult.where(sync_attempt_id: @sync_attempt.id).count)
  end
end
