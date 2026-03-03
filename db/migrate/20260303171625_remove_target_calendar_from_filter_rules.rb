class RemoveTargetCalendarFromFilterRules < ActiveRecord::Migration[8.1]
  def change
    remove_column :filter_rules, :target_calendar_identifier, :string
    remove_column :filter_rules, :target_calendar_display_name, :string
  end
end
