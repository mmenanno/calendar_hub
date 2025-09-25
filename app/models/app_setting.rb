# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :default_time_zone, presence: true
  validates :default_sync_frequency_minutes, presence: true, numericality: { greater_than: 0 }

  class << self
    def instance
      first_or_create!(default_time_zone: "UTC", default_sync_frequency_minutes: 60)
    end
  end
end
