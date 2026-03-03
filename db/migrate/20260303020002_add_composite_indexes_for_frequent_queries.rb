# frozen_string_literal: true

class AddCompositeIndexesForFrequentQueries < ActiveRecord::Migration[8.0]
  def change
    # Supports CalendarEvent.upcoming.where(sync_exempt: false) — the main events index page
    add_index :calendar_events, [:starts_at, :sync_exempt],
              name: "index_calendar_events_on_starts_at_and_sync_exempt"

    # Supports cancel_missing_events queries filtering by source + status
    add_index :calendar_events, [:calendar_source_id, :status],
              name: "index_calendar_events_on_source_and_status"
  end
end
