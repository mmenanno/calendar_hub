# frozen_string_literal: true

class SyncEventResult < ApplicationRecord
  belongs_to :sync_attempt
  belongs_to :calendar_event, optional: true

  scope :failures, -> { where(success: false) }

  class << self
    # First `limit` failures for each of the given attempts, in one query.
    # Returns a hash of sync_attempt_id => [SyncEventResult].
    def first_failures_by_attempt(attempt_ids, limit: 3)
      return {} if attempt_ids.blank?

      ranked = failures
        .where(sync_attempt_id: attempt_ids)
        .select("sync_event_results.*, ROW_NUMBER() OVER (PARTITION BY sync_attempt_id ORDER BY id) AS failure_rank")

      from(ranked, :sync_event_results)
        .where(failure_rank: ..limit)
        .order(:sync_attempt_id, :id)
        .group_by(&:sync_attempt_id)
    end
  end
end
