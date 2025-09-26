# frozen_string_literal: true

class CacheWarmupJob < ApplicationJob
  queue_as :default

  def perform
    CalendarHub::CacheWarmer.warm_search_caches
  end
end
