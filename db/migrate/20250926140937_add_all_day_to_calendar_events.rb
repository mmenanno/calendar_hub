# frozen_string_literal: true

class AddAllDayToCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_column(:calendar_events, :all_day, :boolean, default: false, null: false)
    add_index(:calendar_events, :all_day)
  end
end
