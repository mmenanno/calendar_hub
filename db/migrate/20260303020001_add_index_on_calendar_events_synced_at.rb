# frozen_string_literal: true

class AddIndexOnCalendarEventsSyncedAt < ActiveRecord::Migration[8.0]
  def change
    add_index :calendar_events, [:calendar_source_id, :synced_at],
              name: "index_calendar_events_on_source_and_synced_at"
  end
end
