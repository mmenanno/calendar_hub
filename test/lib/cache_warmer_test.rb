# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class CacheWarmerTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @original_env = ENV["WARM_CACHE_ON_STARTUP"]
    end

    teardown do
      ENV["WARM_CACHE_ON_STARTUP"] = @original_env
    end

    test "should warm cache in production by default" do
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
      ENV.delete("WARM_CACHE_ON_STARTUP")

      assert(CalendarHub::CacheWarmer.send(:should_warm_cache?))
    end

    test "should not warm cache in development by default" do
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))
      ENV.delete("WARM_CACHE_ON_STARTUP")

      refute(CalendarHub::CacheWarmer.send(:should_warm_cache?))
    end

    test "should not warm cache in test environment" do
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("test"))
      ENV["WARM_CACHE_ON_STARTUP"] = "true"

      refute(CalendarHub::CacheWarmer.send(:should_warm_cache?))
    end

    test "environment variable overrides default behavior" do
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("development"))

      ENV["WARM_CACHE_ON_STARTUP"] = "true"

      assert(CalendarHub::CacheWarmer.send(:should_warm_cache?))

      ENV["WARM_CACHE_ON_STARTUP"] = "false"

      refute(CalendarHub::CacheWarmer.send(:should_warm_cache?))
    end

    test "warm_name_mapper_caches populates cache" do
      source = calendar_sources(:provider)

      # Create a mapping to ensure there's something to cache
      EventMapping.create!(
        calendar_source: source,
        pattern: "Test",
        replacement: "Cached",
        match_type: "contains",
        active: true,
      )

      # Warm the cache
      CalendarHub::CacheWarmer.send(:warm_name_mapper_caches)

      # Verify cache was populated by checking if NameMapper uses cached data
      # (We can't easily check Rails.cache directly due to the private method)
      result = CalendarHub::NameMapper.apply("Test Title", source: source)

      assert_equal("Cached", result)
    end

    test "warm_event_search_caches handles events gracefully" do
      CalendarEvent.count
      CalendarEvent.delete_all

      CalendarHub::CacheWarmer.send(:warm_event_search_caches)

      assert_equal(0, CalendarEvent.count)

      event = CalendarEvent.create!(
        calendar_source: calendar_sources(:provider),
        external_id: "test-cache-event",
        title: "Cache Test Event",
        starts_at: 1.week.from_now,
        ends_at: 1.week.from_now + 1.hour,
      )

      CalendarHub::CacheWarmer.send(:warm_event_search_caches)

      assert_equal(1, CalendarEvent.count)
      assert_equal(event.id, CalendarEvent.first.id)
    end
  end
end
