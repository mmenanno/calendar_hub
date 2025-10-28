# frozen_string_literal: true

class CleanupStaleSyncAttemptsJob < ApplicationJob
  # Default threshold for considering a sync attempt stale
  DEFAULT_THRESHOLD = 2.hours

  def perform(threshold: DEFAULT_THRESHOLD)
    with_error_tracking(context: "cleanup stale sync attempts") do
      stale_attempts = SyncAttempt.stale(threshold: threshold)
      count = stale_attempts.count

      return if count.zero?

      Rails.logger.warn("[CleanupStaleSyncAttemptsJob] Found #{count} stale sync attempts, marking as failed")

      stale_attempts.find_each do |attempt|
        # Check if there's a corresponding failed job to understand why it failed
        job = find_failed_job(attempt)
        failure_reason = extract_failure_reason(job)

        message = "Sync attempt timed out after #{threshold.inspect}"
        message += " - #{failure_reason}" if failure_reason

        attempt.finish(status: :failed, message: message)

        Rails.logger.warn(
          "[CleanupStaleSyncAttemptsJob] Marked stale attempt #{attempt.id} " \
            "for source #{attempt.calendar_source_id} as failed (created at #{attempt.created_at})" \
            "#{" - Reason: #{failure_reason}" if failure_reason}",
        )
      end

      Rails.logger.info("[CleanupStaleSyncAttemptsJob] Cleaned up #{count} stale sync attempts")
    end
  end

  private

  def find_failed_job(attempt)
    return unless defined?(SolidQueue::Job)

    SolidQueue::Job.find_by(
      class_name: "SyncCalendarJob",
      active_job_id: attempt.id.to_s,
    ) || SolidQueue::Job.where(
      class_name: "SyncCalendarJob",
    ).where("arguments LIKE ?", "%attempt_id: #{attempt.id}%").first
  end

  def extract_failure_reason(job)
    return unless job
    return unless defined?(SolidQueue::FailedExecution)

    failed_execution = SolidQueue::FailedExecution.find_by(job_id: job.id)
    return unless failed_execution

    error_data = failed_execution.error
    return unless error_data.is_a?(Hash)

    exception_class = error_data["exception_class"]
    message = error_data["message"]

    # Identify specific error types
    if exception_class == "ActiveRecord::StatementTimeout" && message&.include?("database is locked")
      "SQLite database lock contention"
    elsif exception_class == "ActiveRecord::StatementTimeout"
      "Database timeout"
    elsif exception_class == "ActiveRecord::Deadlocked"
      "Database deadlock"
    elsif exception_class && message
      "#{exception_class}: #{message.truncate(100)}"
    else
      "Job failed in queue"
    end
  rescue => e
    Rails.logger.debug { "[CleanupStaleSyncAttemptsJob] Failed to extract failure reason: #{e.message}" }
    nil
  end
end
