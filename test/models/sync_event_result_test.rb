# frozen_string_literal: true

require "test_helper"

class SyncEventResultTest < ActiveSupport::TestCase
  def setup
    @source = calendar_sources(:provider)
    @sync_attempt = SyncAttempt.create!(calendar_source: @source, status: :success)
    @calendar_event = calendar_events(:provider_consult)
  end

  test "belongs to sync_attempt" do
    result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      external_id: "test-123",
      action: "upsert",
      success: true,
      occurred_at: Time.current,
    )

    assert_equal(@sync_attempt, result.sync_attempt)
  end

  test "belongs to calendar_event optionally" do
    result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      calendar_event: @calendar_event,
      external_id: "test-456",
      action: "upsert",
      success: true,
      occurred_at: Time.current,
    )

    assert_equal(@calendar_event, result.calendar_event)
  end

  test "can be created without calendar_event" do
    result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      external_id: "test-789",
      action: "delete",
      success: false,
      occurred_at: Time.current,
    )

    assert_nil(result.calendar_event)
    assert_predicate(result, :valid?)
  end

  test "failures scope returns only failed results" do
    success_result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      calendar_event: @calendar_event,
      external_id: "success-123",
      action: "upsert",
      success: true,
      occurred_at: Time.current,
    )

    failure_result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      external_id: "failure-456",
      action: "delete",
      success: false,
      occurred_at: Time.current,
    )

    failures = SyncEventResult.failures

    assert_includes(failures, failure_result)
    refute_includes(failures, success_result)
  end

  test "failures scope can be empty" do
    SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      calendar_event: @calendar_event,
      external_id: "success-789",
      action: "upsert",
      success: true,
      occurred_at: Time.current,
    )

    failures = SyncEventResult.failures

    assert_empty(failures)
  end

  test "inherits from ApplicationRecord" do
    assert_operator(SyncEventResult, :<, ApplicationRecord)
  end

  test "requires sync_attempt" do
    result = SyncEventResult.new(success: true)

    refute_predicate(result, :valid?)
    assert_includes(result.errors[:sync_attempt], "must exist")
  end

  test "success can be true or false" do
    success_result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      external_id: "success-abc",
      action: "upsert",
      success: true,
      occurred_at: Time.current,
    )

    failure_result = SyncEventResult.create!(
      sync_attempt: @sync_attempt,
      external_id: "failure-def",
      action: "delete",
      success: false,
      occurred_at: Time.current,
    )

    assert_predicate(success_result, :success)
    refute_predicate(failure_result, :success)
  end

  test "first_failures_by_attempt returns at most limit failures per attempt in one query" do
    other_attempt = SyncAttempt.create!(calendar_source: calendar_sources(:ics_feed), status: :failed)
    failures = Array.new(5) do |i|
      SyncEventResult.create!(sync_attempt: @sync_attempt, external_id: "f-#{i}", action: "upsert", success: false, error_message: "boom", occurred_at: Time.current)
    end
    SyncEventResult.create!(sync_attempt: @sync_attempt, external_id: "ok", action: "upsert", success: true, occurred_at: Time.current)
    other_failure = SyncEventResult.create!(sync_attempt: other_attempt, external_id: "o-1", action: "delete", success: false, occurred_at: Time.current)

    result = assert_queries_count(1) { SyncEventResult.first_failures_by_attempt([@sync_attempt.id, other_attempt.id], limit: 3) }

    assert_equal(failures.first(3), result[@sync_attempt.id])
    assert_equal([other_failure], result[other_attempt.id])
  end

  test "first_failures_by_attempt returns an empty hash without ids" do
    assert_empty(SyncEventResult.first_failures_by_attempt([]))
  end
end
