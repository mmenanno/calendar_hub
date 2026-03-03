# frozen_string_literal: true

class AddTargetCalendarToFilterRules < ActiveRecord::Migration[8.1]
  def change
    add_column :filter_rules, :target_calendar_identifier, :string
    add_column :filter_rules, :target_calendar_display_name, :string
  end
end
