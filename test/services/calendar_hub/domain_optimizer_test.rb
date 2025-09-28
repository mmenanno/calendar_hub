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

    test "extract_apex_domain handles URI parsing errors" do
      # This should trigger URI::InvalidURIError and hit the rescue block
      invalid_uri = "http://[invalid-ipv6-address"

      domain = CalendarHub::DomainOptimizer.extract_apex_domain(invalid_uri)

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

    test "extract_apex_domain handles URLs without host" do
      domain = CalendarHub::DomainOptimizer.extract_apex_domain("file:///local/file.ics")

      assert_equal "", domain
    end

    test "extract_apex_domain handles single part domains" do
      domain = CalendarHub::DomainOptimizer.extract_apex_domain("https://localhost/calendar.ics")

      assert_equal "localhost", domain
    end

    test "extract_apex_domain handles domains with many subdomains" do
      domain = CalendarHub::DomainOptimizer.extract_apex_domain("https://a.b.c.example.com/calendar.ics")

      assert_equal "example.com", domain
    end

    test "optimize_sync_schedule handles empty sources array" do
      schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule([])

      assert_empty(schedule)
    end

    test "optimize_sync_schedule sorts sources by id within domain groups" do
      # Create sources with specific IDs to test sorting
      source_high_id = CalendarSource.create!(
        name: "High ID Source",
        ingestion_url: "https://sub1.example.com/high.ics",
        calendar_identifier: "high",
      )
      source_low_id = CalendarSource.create!(
        name: "Low ID Source",
        ingestion_url: "https://sub2.example.com/low.ics",
        calendar_identifier: "low",
      )

      # Ensure the high ID source actually has a higher ID
      if source_high_id.id < source_low_id.id
        source_high_id, source_low_id = source_low_id, source_high_id
      end

      # Pass them in reverse ID order to verify sorting
      sources = [source_high_id, source_low_id]

      freeze_time do
        schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(sources)

        frozen_time = Time.current

        # Lower ID should get the first slot
        assert_equal(frozen_time, schedule[source_low_id.id])
        assert_equal(frozen_time + 5.minutes, schedule[source_high_id.id])
      end
    ensure
      source_high_id&.destroy
      source_low_id&.destroy
    end

    test "optimize_sync_schedule handles different domains independently" do
      source_domain1 = CalendarSource.create!(
        name: "Domain 1 Source",
        ingestion_url: "https://example.com/calendar.ics",
        calendar_identifier: "domain1",
      )
      source_domain2 = CalendarSource.create!(
        name: "Domain 2 Source",
        ingestion_url: "https://other.com/calendar.ics",
        calendar_identifier: "domain2",
      )

      sources = [source_domain1, source_domain2]

      freeze_time do
        schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(sources)

        frozen_time = Time.current

        # Both should start at the same time since they're different domains
        assert_equal(frozen_time, schedule[source_domain1.id])
        assert_equal(frozen_time, schedule[source_domain2.id])
      end
    ensure
      source_domain1&.destroy
      source_domain2&.destroy
    end

    test "group_sources_by_domain handles sources with unknown domains" do
      source_invalid = CalendarSource.create!(
        name: "Invalid URL Source",
        ingestion_url: "invalid-url",
        calendar_identifier: "invalid",
      )
      source_no_host = CalendarSource.create!(
        name: "No Host Source",
        ingestion_url: "file:///local/file.ics",
        calendar_identifier: "nohost",
      )

      sources = [@source1, source_invalid, source_no_host]
      groups = CalendarHub::DomainOptimizer.group_sources_by_domain(sources)

      assert_equal(3, groups.keys.count)
      assert_includes(groups.keys, "example.com")
      assert_includes(groups.keys, "unknown")
      assert_includes(groups.keys, "")
      assert_equal(1, groups["example.com"].count)
      assert_equal(1, groups["unknown"].count)
      assert_equal(1, groups[""].count)
    ensure
      source_invalid&.destroy
      source_no_host&.destroy
    end
  end
end
