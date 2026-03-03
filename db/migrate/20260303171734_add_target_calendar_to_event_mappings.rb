class AddTargetCalendarToEventMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :event_mappings, :target_calendar_identifier, :string
    add_column :event_mappings, :target_calendar_display_name, :string
    change_column_null :event_mappings, :replacement, true
  end
end
