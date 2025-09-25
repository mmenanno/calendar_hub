# frozen_string_literal: true

class AddDefaultSyncFrequencyToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column(:app_settings, :default_sync_frequency_minutes, :integer, default: 60, null: false)
  end
end
