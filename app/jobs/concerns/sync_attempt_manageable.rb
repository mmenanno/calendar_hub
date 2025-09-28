# frozen_string_literal: true

module SyncAttemptManageable
  extend ActiveSupport::Concern

  private

  def find_or_create_sync_attempt(source, attempt_id)
    attempt_id ? SyncAttempt.find(attempt_id) : SyncAttempt.create!(calendar_source: source, status: :queued)
  end
end
