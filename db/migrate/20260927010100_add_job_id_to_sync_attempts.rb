# frozen_string_literal: true

# Records which ActiveJob owns an attempt, so a retried job keeps its attempt
# while a different job for the same source is skipped.
class AddJobIdToSyncAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column(:sync_attempts, :job_id, :string)
  end
end
