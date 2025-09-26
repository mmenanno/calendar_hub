# frozen_string_literal: true

require "test_helper"

class CacheWarmupJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      CacheWarmupJob.perform_later
    end
  end

  test "executes without errors" do
    # Create some test data to ensure cache warming has something to work with
    source = calendar_sources(:provider)
    EventMapping.create!(
      calendar_source: source,
      pattern: "Test",
      replacement: "Cached",
      match_type: "contains",
      active: true,
    )

    assert_nothing_raised do
      perform_enqueued_jobs do
        CacheWarmupJob.perform_later
      end
    end
  end

  test "calls cache warmer service" do
    # Verify the job calls the cache warmer
    CalendarHub::CacheWarmer.expects(:warm_search_caches).once

    perform_enqueued_jobs do
      CacheWarmupJob.perform_later
    end
  end
end
