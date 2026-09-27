# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  include SyncAttemptManageable

  retry_on CalendarHub::Ingestion::Error, wait: :polynomially_longer, attempts: 5

  # Retry on SQLite lock errors with exponential backoff
  # These can occur when multiple jobs try to write simultaneously
  retry_on ActiveRecord::StatementTimeout, wait: :polynomially_longer, attempts: 5
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # Rescue and conditionally retry SQLite busy exceptions
  rescue_from ActiveRecord::StatementInvalid do |exception|
    raise unless exception.message.include?("database is locked") || exception.message.include?("BusyException")

    # Log the retry attempt
    logger.warn("[SyncCalendarJob] SQLite lock detected, will retry (attempt #{executions}/5)")

    # Retry with exponential backoff for SQLite lock errors (1s, 4s, 9s, 16s, 25s)
    if executions < 5
      retry_job(wait: executions**2, queue: queue_name, priority: priority)
    else
      # Max retries exhausted, let it fail
      logger.error("[SyncCalendarJob] Max retries exhausted for SQLite lock")
      raise
    end

    # Re-raise other StatementInvalid errors
  end

  def perform(calendar_source_id, **options)
    source = CalendarSource.find(calendar_source_id)
    sync_options = build_sync_options(options)
    attempt = nil

    with_error_tracking(context: "sync calendar_source_id=#{calendar_source_id}") do
      # No pessimistic locking needed - schedule_sync already checks for running attempts
      # This prevents blocking other database writes during long-running syncs
      attempt = find_or_create_sync_attempt(source, sync_options[:attempt_id])
      execute_sync(source, attempt, sync_options)
      attempt.finish(status: :success)

      # Track consecutive failure count for health indicators
      if attempt.errors_count.to_i > 0
        source.record_sync_failure!
      else
        source.record_sync_success!
      end
    end
  rescue ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked, ActiveRecord::StatementInvalid => exception
    # These will be retried automatically, but update attempt if we have one
    if attempt && !attempt.finished_at
      retry_msg = if exception.is_a?(ActiveRecord::StatementInvalid) &&
          (exception.message.include?("database is locked") || exception.message.include?("BusyException"))
        "SQLite lock, will retry"
      else
        "Lock timeout, will retry"
      end
      attempt.update(message: "#{retry_msg}: #{exception.message.truncate(200)}")
    end
    raise
  rescue StandardError => exception
    attempt&.finish(status: :failed, message: exception.message) unless attempt&.finished_at
    source&.record_sync_failure!
    raise
  end

  private

  def build_sync_options(options)
    { attempt_id: options[:attempt_id] }
  end

  def execute_sync(source, attempt, _options)
    CalendarHub::Sync::SyncService.new(source: source, observer: attempt).call
  end
end
