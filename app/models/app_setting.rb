# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :default_time_zone, presence: true

  class << self
    def instance
      first_or_create!(default_time_zone: "UTC")
    end
  end
end
