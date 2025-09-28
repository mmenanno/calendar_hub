# frozen_string_literal: true

require "test_helper"

class SyncCalendarJobTest < ActiveJob::TestCase
  test "invokes sync service" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id)
  end

  test "uses existing attempt when attempt_id is provided" do
    source = calendar_sources(:provider)
    attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

    CalendarHub::Sync::EnhancedSyncService.expects(:new).with(source: source, observer: attempt).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id, attempt_id: attempt.id)

    assert_equal "success", attempt.reload.status
  end

  test "raises error when attempt_id is provided but attempt not found" do
    source = calendar_sources(:provider)
    non_existent_id = 99999

    # Should raise ActiveRecord::RecordNotFound when attempt doesn't exist
    assert_raises(ActiveRecord::RecordNotFound) do
      SyncCalendarJob.perform_now(source.id, attempt_id: non_existent_id)
    end
  end

  test "handles exceptions and marks attempt as failed" do
    source = calendar_sources(:provider)
    error_message = "Sync failed"

    # Clear any existing attempts
    source.sync_attempts.destroy_all

    service_mock = mock
    service_mock.expects(:call).raises(StandardError.new(error_message))
    CalendarHub::Sync::EnhancedSyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(service_mock)

    # Create the job and run it manually to avoid transaction issues
    job = SyncCalendarJob.new(source.id)

    assert_raises(StandardError) do
      job.perform(source.id)
    end

    # Verify attempt was created and marked as failed
    attempts = SyncAttempt.where(calendar_source: source)

    assert_equal(1, attempts.count, "Expected exactly one sync attempt to be created")

    attempt = attempts.first

    assert_equal("failed", attempt.status)
    assert_equal(error_message, attempt.message)
  end

  test "uses enhanced sync service by default" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::EnhancedSyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id)
  end

  test "uses regular sync service when use_enhanced_sync is false" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id, use_enhanced_sync: false)
  end

  test "creates new attempt when attempt_id is not provided" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::EnhancedSyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(mock(call: true))

    # Don't pass attempt_id (defaults to nil) - should create new attempt
    SyncCalendarJob.perform_now(source.id)

    # Should create a new attempt since attempt_id is nil
    assert(source.sync_attempts.exists?(status: "success"))
  end
end
