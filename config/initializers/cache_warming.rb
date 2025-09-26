# frozen_string_literal: true

module CalendarHub
  class CacheWarmer
    class << self
      def warm_search_caches
        Rails.logger.info("[CacheWarmer] Starting cache warming...")
        warm_name_mapper_caches
        warm_event_search_caches
        Rails.logger.info("[CacheWarmer] Cache warming completed successfully")
      rescue => e
        Rails.logger.warn("[CacheWarmer] Cache warming failed: #{e.message}")
      end

      private

      def should_warm_cache?
        case Rails.env
        when "production"
          ENV.fetch("WARM_CACHE_ON_STARTUP", "true") == "true"
        when "development"
          ENV.fetch("WARM_CACHE_ON_STARTUP", "false") == "true"
        when "test"
          false
        else
          false
        end
      end

      def warm_name_mapper_caches
        CalendarSource.find_each do |source|
          CalendarHub::NameMapper.send(:cached_active_mappings, source)
        end

        CalendarHub::NameMapper.send(:cached_active_mappings, nil)

        Rails.logger.debug("[CacheWarmer] Name mapper caches warmed")
      end

      def warm_event_search_caches
        recent_events = CalendarEvent.upcoming.limit(50).includes(:calendar_source)

        recent_events.find_each do |event|
          presenter = CalendarEventPresenter.new(event, nil)
          presenter.title

          cache_key = "event_search_data/#{event.id}/#{event.updated_at.to_i}"
          Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
            {
              original_title: event.title.to_s.downcase,
              mapped_title: presenter.title.to_s.downcase,
              location: event.location.to_s.downcase,
            }
          end
        end

        Rails.logger.debug { "[CacheWarmer] Event search caches warmed for #{recent_events.count} events" }
      end
    end
  end
end

Rails.application.config.after_initialize do
  # Schedule cache warming after initialization
  if CalendarHub::CacheWarmer.send(:should_warm_cache?)
    CacheWarmupJob.set(wait: 1.second).perform_later
  end
end
