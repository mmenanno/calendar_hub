# frozen_string_literal: true

class CreateSyncMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_metrics do |t|
      t.references :calendar_source, null: false, foreign_key: true
      t.datetime :occurred_at, null: false
      t.integer :upserts_count, null: false, default: 0
      t.integer :deletes_count, null: false, default: 0
      t.integer :errors_count, null: false, default: 0
      t.integer :duration_ms, null: false, default: 0

      t.timestamps
    end

    add_index :sync_metrics, [:calendar_source_id, :occurred_at], name: "idx_sync_metrics_source_occurred"
  end
end
