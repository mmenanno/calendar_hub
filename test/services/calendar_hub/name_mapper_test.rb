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
  end
end
