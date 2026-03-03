# frozen_string_literal: true

class AddConsecutiveSyncFailuresToCalendarSources < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_sources, :consecutive_sync_failures, :integer, null: false, default: 0
  end
end
