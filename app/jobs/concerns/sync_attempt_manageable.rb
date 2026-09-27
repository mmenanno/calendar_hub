# frozen_string_literal: true

module SyncAttemptManageable
  extend ActiveSupport::Concern

  private

  # Returns the attempt this job execution should report to, or nil when
  # another job owns the source's active attempt (the caller should skip).
  #
  # Attempts record the ActiveJob id that owns them, so a retried execution
  # of the same job keeps its attempt while a different job is turned away
  # instead of running a second, concurrent sync of the same source.
  def find_or_create_sync_attempt(source, attempt_id)
    return claim_sync_attempt(SyncAttempt.find(attempt_id)) if attempt_id

    SyncAttempt.create!(calendar_source: source, status: :queued, job_id: job_id)
  rescue ActiveRecord::RecordNotUnique
    # idx_unique_active_sync_attempt_per_source: an attempt is already active.
    active = source.sync_attempts.where(status: ["queued", "running"]).order(created_at: :desc).first
    active if active&.job_id.present? && active.job_id == job_id
  end

  def claim_sync_attempt(attempt)
    # Finished (e.g. marked stale) or owned by another job: do not run.
    return if attempt.finished_at.present?
    return if attempt.job_id.present? && attempt.job_id != job_id

    attempt.update_column(:job_id, job_id) if attempt.job_id.blank?
    attempt
  end
end
