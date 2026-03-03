# frozen_string_literal: true

class AddCompositeIndexOnSyncAttempts < ActiveRecord::Migration[8.0]
  def change
    add_index :sync_attempts, [:calendar_source_id, :status, :created_at],
              name: "index_sync_attempts_on_source_status_created_at"
  end
end
