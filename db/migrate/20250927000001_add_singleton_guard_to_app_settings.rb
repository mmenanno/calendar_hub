# frozen_string_literal: true

class AddSingletonGuardToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :app_settings, :singleton_guard, :integer, default: 0, null: false
    add_index :app_settings, :singleton_guard, unique: true
  end
end
