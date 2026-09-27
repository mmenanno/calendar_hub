# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  include SyncAttemptManageable

  queue_as :sync

  MAX_ATTEMPTS = 5
  # Transient failures: the job is retried and the attempt stays active, so
  # the scheduler does not start a parallel sync while a retry is pending.
  # SQLite "database is locked" surfaces as ActiveRecord::StatementTimeout.
  RETRYABLE_ERRORS = [
    CalendarHub::Ingestion::Error,
    ActiveRecord::StatementTimeout,
    ActiveRecord::Deadlocked,
    ActiveRecord::ConnectionTimeoutError,
  ].freeze

  # At most one sync per source runs at a time; a second job for the same
  # source waits until the first finishes.
  limits_concurrency to: 1, key: ->(calendar_source_id, *) { calendar_source_id }, duration: 2.hours

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS) do |job, error|
    job.send(:fail_sync!, error)
    raise error
  end

  def perform(calendar_source_id, **options)
    @source = CalendarSource.find(calendar_source_id)

    with_error_tracking(context: "sync calendar_source_id=#{calendar_source_id}") do
      @attempt = find_or_create_sync_attempt(@source, options[:attempt_id])
      if @attempt.nil?
        Rails.logger.info("[SyncCalendarJob] Another sync is active for source=#{calendar_source_id}; skipping")
        return
      end

      CalendarHub::Sync::SyncService.new(source: @source, observer: @attempt, force: options[:force] == true).call
      @attempt.finish(status: :success) unless @attempt.finished_at

      # A sync that completed with per-event errors still counts as a failure
      # for health indicators (but does not trigger backoff).
      if @attempt.errors_count.to_i.positive?
        @source.record_sync_failure!
      else
        @source.record_sync_success!
      end
    end
  rescue *RETRYABLE_ERRORS => exception
    # retry_on re-enqueues the job (or calls fail_sync! once attempts are
    # exhausted); keep the attempt active meanwhile.
    @attempt.note!("Attempt #{executions}/#{MAX_ATTEMPTS} failed, will retry: #{exception.message.truncate(300)}") if @attempt && !@attempt.finished_at && executions < MAX_ATTEMPTS
    raise
  rescue StandardError => exception
    fail_sync!(exception)
    raise
  end

  private

  # Records the final failure of this sync exactly once (not per retry).
  def fail_sync!(error)
    return if @failure_recorded

    @failure_recorded = true
    @attempt.finish(status: :failed, message: error.message.truncate(500)) if @attempt && !@attempt.finished_at
    @source&.record_sync_failure!
    ActiveSupport::Notifications.instrument(
      "calendar_hub.sync",
      source_id: @source&.id,
      failed: true,
      fetched: 0,
      upserts: 0,
      deletes: 0,
      errors: 1,
      duration_ms: 0,
    )
  end
end
