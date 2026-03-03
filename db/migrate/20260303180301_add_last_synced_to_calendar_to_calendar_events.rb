class AddLastSyncedToCalendarToCalendarEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :calendar_events, :last_synced_to_calendar, :string

    # Backfill previously-synced events: they were all synced to their source's
    # default calendar (destination override was broken before this release).
    execute <<~SQL
      UPDATE calendar_events
      SET last_synced_to_calendar = (
        SELECT calendar_sources.calendar_identifier
        FROM calendar_sources
        WHERE calendar_sources.id = calendar_events.calendar_source_id
      )
      WHERE synced_at IS NOT NULL
    SQL
  end

  def down
    remove_column :calendar_events, :last_synced_to_calendar
  end
end
