# frozen_string_literal: true

class AddAutoSyncToCalendarSources < ActiveRecord::Migration[8.0]
  def change
    add_column(:calendar_sources, :sync_frequency_minutes, :integer)
    add_column(:calendar_sources, :auto_sync_enabled, :boolean, default: true, null: false)
    add_column(:calendar_sources, :ics_feed_etag, :string)
    add_column(:calendar_sources, :ics_feed_last_modified, :string)
    add_column(:calendar_sources, :last_change_hash, :string)

    add_index(:calendar_sources, :auto_sync_enabled)
    add_index(:calendar_sources, :sync_frequency_minutes)
  end
end
