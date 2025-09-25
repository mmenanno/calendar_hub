# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class DomainOptimizerTest < ActiveSupport::TestCase
    setup do
      @source1 = calendar_sources(:provider)
      @source2 = calendar_sources(:ics_feed)
      @source1.update!(ingestion_url: "https://sub1.example.com/calendar.ics")
      @source2.update!(ingestion_url: "https://sub2.example.com/calendar.ics")
    end

    test "extracts apex domain correctly" do
      assert_equal "example.com", CalendarHub::DomainOptimizer.extract_apex_domain("https://sub.example.com/path")
      assert_equal "example.com", CalendarHub::DomainOptimizer.extract_apex_domain("https://example.com/path")
      assert_equal "github.com", CalendarHub::DomainOptimizer.extract_apex_domain("https://api.github.com/path")
    end

    test "groups sources by apex domain" do
      @source3 = CalendarSource.create!(
        name: "Test Source 3",
        ingestion_url: "https://different.org/calendar.ics",
        calendar_identifier: "test3",
      )

      sources = [@source1, @source2, @source3]
      groups = CalendarHub::DomainOptimizer.group_sources_by_domain(sources)

      assert_equal 2, groups.keys.count
      assert_equal 2, groups["example.com"].count
      assert_equal 1, groups["different.org"].count
    end

    test "handles invalid URLs gracefully" do
      @source1.update!(ingestion_url: "not-a-valid-url")

      domain = CalendarHub::DomainOptimizer.extract_apex_domain(@source1.ingestion_url)

      assert_equal "unknown", domain
    end

    test "optimizes sync schedule with time gaps" do
      sources = [@source1, @source2]

      freeze_time do
        schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(sources)

        frozen_time = Time.current

        assert_equal frozen_time, schedule[@source1.id]
        assert_equal frozen_time + 5.minutes, schedule[@source2.id]
      end
    end

    test "allows custom window minutes" do
      sources = [@source1, @source2]

      freeze_time do
        schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(sources, window_minutes: 10)

        frozen_time = Time.current

        assert_equal frozen_time, schedule[@source1.id]
        assert_equal frozen_time + 10.minutes, schedule[@source2.id]
      end
    end
  end
end
