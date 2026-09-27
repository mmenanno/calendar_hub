# frozen_string_literal: true

# Audits and sync event results reference calendar_events (and results reference
# sync_attempts) without ON DELETE, so destroying an event that has history
# raised a foreign key error, and pruning old attempts required deleting their
# results first. Let the database cascade instead.
#
# SQLite can't alter a constraint in place; Rails rebuilds each table (copy,
# drop, rename) when a foreign key is removed or added.
class CascadeDeletesToEventAuditsAndSyncResults < ActiveRecord::Migration[8.1]
  FOREIGN_KEYS = [
    [:calendar_event_audits, :calendar_events],
    [:sync_event_results, :calendar_events],
    [:sync_event_results, :sync_attempts],
  ].freeze

  def up
    FOREIGN_KEYS.each do |from_table, to_table|
      remove_foreign_key(from_table, to_table)
      add_foreign_key(from_table, to_table, on_delete: :cascade)
    end
  end

  def down
    FOREIGN_KEYS.each do |from_table, to_table|
      remove_foreign_key(from_table, to_table)
      add_foreign_key(from_table, to_table)
    end
  end
end
