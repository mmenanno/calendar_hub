# frozen_string_literal: true

class AddImportStartDateToCalendarSources < ActiveRecord::Migration[8.0]
  def change
    add_column(:calendar_sources, :import_start_date, :datetime)
    add_index(:calendar_sources, :import_start_date)

    # Set import_start_date to current time for existing sources
    # This ensures existing sources continue to work as before
    reversible do |dir|
      dir.up do
        execute("UPDATE calendar_sources SET import_start_date = created_at WHERE import_start_date IS NULL")
      end
    end
  end
end
