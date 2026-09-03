# frozen_string_literal: true

module SyncAttemptManageable
  extend ActiveSupport::Concern

  private

  def find_or_create_sync_attempt(source, attempt_id)
    return SyncAttempt.find(attempt_id) if attempt_id

    SyncAttempt.create!(calendar_source: source, status: :queued)
  rescue ActiveRecord::RecordNotUnique
    # Another worker already created the active attempt for this source
    # (enforced by idx_unique_active_sync_attempt_per_source) -- reuse it
    # instead of crashing the job.
    source.sync_attempts.where(status: ["queued", "running"]).order(created_at: :desc).first || raise
  end
end
