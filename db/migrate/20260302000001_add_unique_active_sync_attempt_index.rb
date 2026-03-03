# frozen_string_literal: true

class AddUniqueActiveSyncAttemptIndex < ActiveRecord::Migration[8.0]
  def up
    # Mark any stale queued/running attempts as failed so the unique index can be created.
    # Keep only the most recent active attempt per source.
    execute <<~SQL
      UPDATE sync_attempts
      SET status = 'failed', finished_at = CURRENT_TIMESTAMP, message = 'Marked failed by migration: stale active attempt'
      WHERE status IN ('queued', 'running')
        AND id NOT IN (
          SELECT MAX(id)
          FROM sync_attempts
          WHERE status IN ('queued', 'running')
          GROUP BY calendar_source_id
        )
    SQL

    add_index :sync_attempts, :calendar_source_id,
      unique: true,
      where: "status IN ('queued', 'running')",
      name: "idx_unique_active_sync_attempt_per_source"
  end

  def down
    remove_index :sync_attempts, name: "idx_unique_active_sync_attempt_per_source"
  end
end
