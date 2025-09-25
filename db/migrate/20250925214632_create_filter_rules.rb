# frozen_string_literal: true

class CreateFilterRules < ActiveRecord::Migration[8.0]
  def change
    create_table(:filter_rules) do |t|
      t.references(:calendar_source, null: true, foreign_key: true)
      t.string(:match_type, null: false, default: "contains")
      t.string(:pattern, null: false)
      t.string(:field_name, null: false, default: "title")
      t.boolean(:case_sensitive, null: false, default: false)
      t.boolean(:active, null: false, default: true)
      t.integer(:position, null: false, default: 0)

      t.timestamps
    end

    add_index(:filter_rules, [:calendar_source_id, :active, :position], name: "idx_filter_rules_source_active_position")
  end
end
