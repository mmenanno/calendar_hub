# frozen_string_literal: true

require "test_helper"

class SyncCalendarJobTest < ActiveJob::TestCase
  test "invokes sync service" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt), force: false).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id)
  end

  test "uses existing attempt when attempt_id is provided" do
    source = calendar_sources(:provider)
    attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: attempt, force: false).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id, attempt_id: attempt.id)

    assert_equal("success", attempt.reload.status)
  end

  test "raises error when attempt_id is provided but attempt not found" do
    source = calendar_sources(:provider)
    non_existent_id = 99_999

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
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt), force: false).returns(service_mock)

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

  test "creates new attempt when attempt_id is not provided" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt), force: false).returns(mock(call: true))

    # Don't pass attempt_id (defaults to nil) - should create new attempt
    SyncCalendarJob.perform_now(source.id)

    # Should create a new attempt since attempt_id is nil
    assert(source.sync_attempts.exists?(status: "success"))
  end

  test "skips instead of running a second sync when another job owns the active attempt" do
    source = calendar_sources(:provider)
    existing_attempt = source.sync_attempts.create!(status: :running, job_id: "another-job")

    CalendarHub::Sync::SyncService.expects(:new).never

    SyncCalendarJob.perform_now(source.id)

    assert_equal("running", existing_attempt.reload.status)
  end

  test "skips when the given attempt belongs to another job" do
    source = calendar_sources(:provider)
    attempt = source.sync_attempts.create!(status: :queued, job_id: "another-job")

    CalendarHub::Sync::SyncService.expects(:new).never

    SyncCalendarJob.perform_now(source.id, attempt_id: attempt.id)
  end

  test "a retried execution keeps its own attempt" do
    source = calendar_sources(:provider)
    job = SyncCalendarJob.new(source.id)
    attempt = source.sync_attempts.create!(status: :running, job_id: job.job_id)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: attempt, force: false).returns(mock(call: true))

    job.perform_now

    assert_equal("success", attempt.reload.status)
  end

  test "passes force to the sync service" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt), force: true).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id, force: true)
  end

  test "keeps the attempt active and does not count a failure while a retry is pending" do
    source = calendar_sources(:provider)
    source.update!(consecutive_sync_failures: 0)
    CalendarHub::Sync::SyncService.any_instance.stubs(:call).raises(CalendarHub::Ingestion::Error, "HTTP 503")

    assert_enqueued_with(job: SyncCalendarJob) do
      SyncCalendarJob.perform_now(source.id)
    end

    attempt = source.sync_attempts.order(:created_at).last

    assert_nil(attempt.finished_at)
    assert_match(/will retry/, attempt.message)
    assert_equal(0, source.reload.consecutive_sync_failures)
  end

  test "records one failure once retries are exhausted" do
    source = calendar_sources(:provider)
    source.update!(consecutive_sync_failures: 0)
    CalendarHub::Sync::SyncService.any_instance.stubs(:call).raises(CalendarHub::Ingestion::Error, "HTTP 503")
    job = SyncCalendarJob.new(source.id)
    job.executions = SyncCalendarJob::MAX_ATTEMPTS - 1
    job.exception_executions = { SyncCalendarJob::RETRYABLE_ERRORS.to_s => SyncCalendarJob::MAX_ATTEMPTS - 1 }

    assert_raises(CalendarHub::Ingestion::Error) { job.perform_now }

    attempt = source.sync_attempts.order(:created_at).last

    assert_predicate(attempt, :failed?)
    assert_equal("HTTP 503", attempt.message)
    assert_equal(1, source.reload.consecutive_sync_failures)
  end

  test "runs on the sync queue with one sync per source" do
    job = SyncCalendarJob.new(42, attempt_id: 7)

    assert_equal("sync", job.queue_name)
    assert_equal(1, SyncCalendarJob.concurrency_limit)
    assert_includes(job.concurrency_key, "42")
  end

  # FEAT-006: Sync failure tracking

  test "records sync success and resets consecutive_sync_failures" do
    source = calendar_sources(:provider)
    source.update_column(:consecutive_sync_failures, 3)

    # Mock a successful sync with no errors
    attempt_mock = mock("attempt")
    attempt_mock.stubs(:id).returns(nil)
    attempt_mock.stubs(:errors_count).returns(0)
    attempt_mock.expects(:finish).with(status: :success)
    attempt_mock.stubs(:finished_at).returns(nil)
    attempt_mock.stubs(:started_at).returns(nil)
    attempt_mock.stubs(:started_at=)
    attempt_mock.stubs(:update!)
    attempt_mock.stubs(:save!)
    attempt_mock.stubs(:status).returns("running")

    service_mock = mock("service")
    service_mock.expects(:call)

    CalendarHub::Sync::SyncService.expects(:new).returns(service_mock)
    SyncAttempt.stubs(:find_by).returns(nil)
    SyncAttempt.stubs(:create!).returns(attempt_mock)

    SyncCalendarJob.perform_now(source.id)

    assert_equal(0, source.reload.consecutive_sync_failures)
  end

  test "records sync failure and increments consecutive_sync_failures" do
    source = calendar_sources(:provider)
    source.update_column(:consecutive_sync_failures, 0)

    service_mock = mock("service")
    service_mock.expects(:call).raises(StandardError.new("Network error"))
    CalendarHub::Sync::SyncService.expects(:new).returns(service_mock)

    assert_raises(StandardError) do
      SyncCalendarJob.perform_now(source.id)
    end

    assert_equal(1, source.reload.consecutive_sync_failures)
  end

  test "re-enqueues itself when the feed fetch fails" do
    source = calendar_sources(:provider)
    CalendarHub::Sync::SyncService.any_instance.stubs(:call).raises(CalendarHub::Ingestion::Error, "HTTP 503")

    assert_enqueued_with(job: SyncCalendarJob) do
      SyncCalendarJob.perform_now(source.id)
    end
  end
end
