# frozen_string_literal: true

namespace :cache do
  desc "Warm up search caches for better performance"
  task warm: :environment do
    puts "Warming up search caches..."
    CalendarHub::CacheWarmer.send(:warm_name_mapper_caches)
    CalendarHub::CacheWarmer.send(:warm_event_search_caches)
    puts "Cache warming completed!"
  end

  desc "Clear all search-related caches"
  task clear_search: :environment do
    puts "Clearing search caches..."

    # Clear name mapper caches
    CalendarSource.find_each do |source|
      cache_key = "name_mapper/active_mappings/#{source.id}"
      Rails.cache.delete(cache_key)
    end
    Rails.cache.delete("name_mapper/active_mappings/global")

    # Clear event search data caches
    pattern = "event_search_data/*"
    Rails.cache.delete_matched(pattern)

    # Clear mapped title caches
    pattern = "mapped_title/*"
    Rails.cache.delete_matched(pattern)

    puts "Search caches cleared!"
  end
end
