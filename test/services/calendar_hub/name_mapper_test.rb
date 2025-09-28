# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class NameMapperTest < ActiveSupport::TestCase
    setup do
      @source = calendar_sources(:provider)
      @event = calendar_events(:provider_consult)
      Rails.cache.clear
    end

    test "applies mappings correctly" do
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Test",
        replacement: "Cached Test",
        match_type: "contains",
        active: true,
      )

      result = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("Cached Test", result)

      result2 = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("Cached Test", result2)
    end

    test "cache is invalidated when mapping changes" do
      mapping = EventMapping.create!(
        calendar_source: @source,
        pattern: "Test",
        replacement: "Original",
        match_type: "contains",
        active: true,
      )

      result1 = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("Original", result1)

      mapping.update!(replacement: "Updated")

      result2 = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("Updated", result2)
    end

    test "cache is invalidated when mapping is destroyed" do
      mapping = EventMapping.create!(
        calendar_source: @source,
        pattern: "Test",
        replacement: "To Be Deleted",
        match_type: "contains",
        active: true,
      )

      result1 = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("To Be Deleted", result1)

      mapping.destroy!

      result2 = CalendarHub::NameMapper.apply("Test Title", source: @source)

      assert_equal("Test Title", result2)
    end

    test "returns original title when blank" do
      assert_nil(CalendarHub::NameMapper.apply(nil, source: @source))
      assert_equal("", CalendarHub::NameMapper.apply("", source: @source))
      assert_equal("   ", CalendarHub::NameMapper.apply("   ", source: @source))
    end

    test "equals match type with case sensitivity" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case sensitive equals
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Exact Match",
        replacement: "Replaced Exact",
        match_type: "equals",
        case_sensitive: true,
        active: true,
      )

      assert_equal("Replaced Exact", CalendarHub::NameMapper.apply("Exact Match", source: @source))
      assert_equal("exact match", CalendarHub::NameMapper.apply("exact match", source: @source)) # Different case, no match

      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case insensitive equals
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Case Test",
        replacement: "Case Replaced",
        match_type: "equals",
        case_sensitive: false,
        active: true,
      )

      assert_equal("Case Replaced", CalendarHub::NameMapper.apply("case test", source: @source))
      assert_equal("Case Replaced", CalendarHub::NameMapper.apply("CASE TEST", source: @source))
    end

    test "contains match type with case sensitivity" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case sensitive contains
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Meeting",
        replacement: "Conference",
        match_type: "contains",
        case_sensitive: true,
        active: true,
      )

      assert_equal("Conference", CalendarHub::NameMapper.apply("Team Meeting Today", source: @source))
      assert_equal("team meeting today", CalendarHub::NameMapper.apply("team meeting today", source: @source)) # Different case, no match

      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case insensitive contains
      EventMapping.create!(
        calendar_source: @source,
        pattern: "urgent",
        replacement: "Priority",
        match_type: "contains",
        case_sensitive: false,
        active: true,
      )

      assert_equal("Priority", CalendarHub::NameMapper.apply("URGENT: Fix bug", source: @source))
      assert_equal("Priority", CalendarHub::NameMapper.apply("This is urgent", source: @source))
    end

    test "regex match type with successful replacement" do
      # Clean up all existing mappings for this source first
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case sensitive regex - exact match
      EventMapping.create!(
        calendar_source: @source,
        pattern: "\\d{2}:\\d{2}",
        replacement: "[TIME]",
        match_type: "regex",
        case_sensitive: true,
        active: true,
      )

      assert_equal("Meeting at [TIME]", CalendarHub::NameMapper.apply("Meeting at 15:30", source: @source))

      # Clean up and create new mapping
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Case insensitive regex - simple word match
      EventMapping.create!(
        calendar_source: @source,
        pattern: "meeting",
        replacement: "Session",
        match_type: "regex",
        case_sensitive: false,
        active: true,
      )

      result = CalendarHub::NameMapper.apply("Team MEETING today", source: @source)

      assert_equal("Team Session today", result)
    end

    test "regex match type with invalid pattern handles RegexpError" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      EventMapping.create!(
        calendar_source: @source,
        pattern: "[invalid regex",
        replacement: "Should not replace",
        match_type: "regex",
        case_sensitive: true,
        active: true,
      )

      # Should return original title when regex is invalid
      assert_equal("Test Title", CalendarHub::NameMapper.apply("Test Title", source: @source))
    end

    test "compare? method with equals mode and case sensitivity" do
      assert(CalendarHub::NameMapper.compare?("Hello", "Hello", case_sensitive: true, mode: :equals))
      refute(CalendarHub::NameMapper.compare?("Hello", "hello", case_sensitive: true, mode: :equals))
      assert(CalendarHub::NameMapper.compare?("Hello", "hello", case_sensitive: false, mode: :equals))
      refute(CalendarHub::NameMapper.compare?("Hello", "hello!", case_sensitive: false, mode: :equals))
    end

    test "compare? method with contains mode and case sensitivity" do
      assert(CalendarHub::NameMapper.compare?("Hello World", "World", case_sensitive: true, mode: :contains))
      refute(CalendarHub::NameMapper.compare?("Hello World", "world", case_sensitive: true, mode: :contains))
      assert(CalendarHub::NameMapper.compare?("Hello World", "world", case_sensitive: false, mode: :contains))
      assert(CalendarHub::NameMapper.compare?("HelloWorld", "world", case_sensitive: false, mode: :contains))
    end

    test "compare? method with invalid mode returns false" do
      refute(CalendarHub::NameMapper.compare?("Hello", "Hello", case_sensitive: true, mode: :invalid))
      refute(CalendarHub::NameMapper.compare?("Hello", "Hello", case_sensitive: true, mode: :invalid_mode))
      refute(CalendarHub::NameMapper.compare?("Hello", "Hello", case_sensitive: false, mode: :unknown))
    end

    test "caching works for global mappings" do
      Rails.cache.clear

      # Create a global mapping (no calendar_source)
      mapping = EventMapping.create!(
        calendar_source: nil,
        pattern: "Global",
        replacement: "Worldwide",
        match_type: "contains",
        active: true,
      )

      # Test with nil source (should use global mappings)
      result1 = CalendarHub::NameMapper.apply("Global Meeting", source: nil)

      assert_equal("Worldwide", result1)

      # Test caching is working - the cached_active_mappings method should have populated the cache
      # Let's verify the cache was populated by checking if the method was called
      result2 = CalendarHub::NameMapper.apply("Global Meeting", source: nil)

      assert_equal("Worldwide", result2)

      # Verify that the mapping is actually being used (this tests the caching indirectly)
      mapping.update!(replacement: "Changed")
      result3 = CalendarHub::NameMapper.apply("Global Meeting", source: nil)

      assert_equal("Changed", result3) # Should get new value since cache was cleared on update
    end

    test "applies first matching rule in order" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Create multiple mappings that could match
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Meeting",
        replacement: "First Match",
        match_type: "contains",
        active: true,
        position: 1,
      )

      EventMapping.create!(
        calendar_source: @source,
        pattern: "Team Meeting",
        replacement: "Second Match",
        match_type: "contains",
        active: true,
        position: 2,
      )

      # Should apply the first matching rule
      result = CalendarHub::NameMapper.apply("Team Meeting Today", source: @source)

      assert_equal("First Match", result)
    end

    test "handles multiple regex patterns with different case sensitivity" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Test case-insensitive regex first (should match both upper and lower case)
      EventMapping.create!(
        calendar_source: @source,
        pattern: "urgent",
        replacement: "Priority",
        match_type: "regex",
        case_sensitive: false,
        active: true,
      )

      # Test with uppercase - should match due to case insensitivity
      result = CalendarHub::NameMapper.apply("URGENT task", source: @source)

      assert_equal("Priority task", result)

      # Test with lowercase - should also match
      result2 = CalendarHub::NameMapper.apply("urgent task", source: @source)

      assert_equal("Priority task", result2)

      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Now test case-sensitive regex
      EventMapping.create!(
        calendar_source: @source,
        pattern: "urgent",
        replacement: "Exact Match",
        match_type: "regex",
        case_sensitive: true,
        active: true,
      )

      # Test with exact case - should match
      result3 = CalendarHub::NameMapper.apply("urgent task", source: @source)

      assert_equal("Exact Match task", result3)

      # Test with different case - should not match
      result4 = CalendarHub::NameMapper.apply("URGENT task", source: @source)

      assert_equal("URGENT task", result4) # Original unchanged
    end

    test "handles source-specific vs global mappings priority" do
      EventMapping.where(calendar_source: [nil, @source]).destroy_all
      Rails.cache.clear

      # Create a global mapping with higher position
      EventMapping.create!(
        calendar_source: nil,
        pattern: "Global",
        replacement: "Global Match",
        match_type: "contains",
        active: true,
        position: 2,
      )

      # Create a source-specific mapping with lower position (should come first)
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Global",
        replacement: "Source Match",
        match_type: "contains",
        active: true,
        position: 1,
      )

      # Source-specific should take priority due to lower position
      result = CalendarHub::NameMapper.apply("Global Meeting", source: @source)

      assert_equal("Source Match", result)

      # Test that global mapping works when there's no source-specific one
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      result2 = CalendarHub::NameMapper.apply("Global Meeting", source: @source)

      assert_equal("Global Match", result2)
    end

    test "handles inactive mappings correctly" do
      EventMapping.where(calendar_source: @source).destroy_all
      Rails.cache.clear

      # Create an inactive mapping first
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Disabled",
        replacement: "Should not apply",
        match_type: "contains",
        case_sensitive: false,
        active: false, # inactive
      )

      # Inactive mapping should not be applied since it's not active
      result1 = CalendarHub::NameMapper.apply("Disabled Test", source: @source)

      assert_equal("Disabled Test", result1)

      # Test that we can verify the mapping exists but is inactive
      all_mappings = EventMapping.where(calendar_source: @source)

      assert_equal(1, all_mappings.count)
      refute(all_mappings.first.active)

      # Now create an active mapping
      EventMapping.create!(
        calendar_source: @source,
        pattern: "Enabled",
        replacement: "Applied",
        match_type: "contains",
        case_sensitive: false,
        active: true,
      )

      # Active mapping should be applied
      result2 = CalendarHub::NameMapper.apply("Enabled Test", source: @source)

      assert_equal("Applied", result2)

      # Inactive mapping should still not be applied
      result3 = CalendarHub::NameMapper.apply("Disabled Test", source: @source)

      assert_equal("Disabled Test", result3)
    end
  end
end
