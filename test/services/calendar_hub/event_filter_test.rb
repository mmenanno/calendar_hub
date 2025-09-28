# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class EventFilterTest < ActiveSupport::TestCase
    include ModelBuilders

    def setup
      @calendar_source = calendar_sources(:provider)
      @event = calendar_events(:provider_consult)
      @event.update!(title: "Team Meeting", description: "Weekly sync", location: "Conference Room A")

      FilterRule.destroy_all
    end

    test "should_filter? returns false when no rules match" do
      refute(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? returns true when rule matches" do
      build_filter_rule(pattern: "Meeting", field_name: :title, match_type: :contains, active: true)

      assert(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? respects calendar source scoping" do
      other_source = calendar_sources(:test_source)

      build_filter_rule(
        calendar_source: other_source,
        pattern: "Meeting",
        field_name: :title,
        match_type: :contains,
      )

      # Event from different source should not be filtered
      refute(CalendarHub::EventFilter.should_filter?(@event))

      # Event from matching source should be filtered
      @event.calendar_source = other_source

      assert(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? ignores inactive rules" do
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: false,
      )

      refute(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "apply_filters sets sync_exempt on matching events" do
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      events = [@event]
      CalendarHub::EventFilter.apply_filters(events)

      assert_predicate(@event, :sync_exempt?)
    end

    test "apply_filters does not modify non-matching events" do
      FilterRule.create!(
        pattern: "Standup",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      events = [@event]
      original_sync_exempt = @event.sync_exempt?
      CalendarHub::EventFilter.apply_filters(events)

      assert_equal(original_sync_exempt, @event.sync_exempt?)
    end

    test "apply_backwards_filtering updates existing events" do
      @event.update!(sync_exempt: false)

      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
        calendar_source: @calendar_source,
      )

      filtered_count = CalendarHub::EventFilter.apply_backwards_filtering(@calendar_source)

      assert_equal(1, filtered_count)
      assert_predicate(@event.reload, :sync_exempt?)
    end

    test "find_re_includable_events finds events that no longer match rules" do
      @event.update!(sync_exempt: true)

      # No rules, so event should be re-includable
      re_includable = CalendarHub::EventFilter.find_re_includable_events(@calendar_source)

      assert_includes(re_includable, @event)
    end

    test "apply_reverse_filtering re-includes events that no longer match" do
      @event.update!(sync_exempt: true)

      CalendarHub::EventFilter.apply_reverse_filtering(@calendar_source)

      refute_predicate(@event.reload, :sync_exempt?)
    end

    test "global rules apply to all sources" do
      other_source = CalendarSource.create!(
        name: "Other Source",
        calendar_identifier: "other-cal",
        ingestion_url: "https://example.com/other.ics",
      )

      other_event = CalendarEvent.create!(
        calendar_source: other_source,
        external_id: "other-event",
        title: "Team Meeting",
        starts_at: 1.hour.from_now,
        ends_at: 2.hours.from_now,
      )

      # Global rule (no calendar_source)
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      assert(CalendarHub::EventFilter.should_filter?(@event))
      assert(CalendarHub::EventFilter.should_filter?(other_event))
    end

    test "multiple rules with OR logic" do
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      FilterRule.create!(
        pattern: "Standup",
        field_name: "description",
        match_type: "contains",
        active: true,
      )

      # Should match first rule
      assert(CalendarHub::EventFilter.should_filter?(@event))

      # Change event to not match first rule but match second
      @event.title = "Daily Check-in"
      @event.description = "Daily standup meeting"

      assert(CalendarHub::EventFilter.should_filter?(@event))

      # Change event to match neither rule
      @event.title = "Code Review"
      @event.description = "Review pull requests"

      refute(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? returns false for blank/nil events" do
      refute(CalendarHub::EventFilter.should_filter?(nil))
    end

    test "apply_filters returns early for blank events" do
      result = CalendarHub::EventFilter.apply_filters(nil)

      assert_nil(result)

      result = CalendarHub::EventFilter.apply_filters([])

      assert_empty(result)
    end

    test "apply_backwards_filtering works without source parameter" do
      @event.update!(sync_exempt: false)

      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      # Test without source parameter (should process all events)
      filtered_count = CalendarHub::EventFilter.apply_backwards_filtering

      assert_equal(1, filtered_count)
      assert_predicate(@event.reload, :sync_exempt?)
    end

    test "find_re_includable_events works without source parameter" do
      @event.update!(sync_exempt: true)

      # Test without source parameter (should find all re-includable events)
      re_includable = CalendarHub::EventFilter.find_re_includable_events

      assert_includes(re_includable, @event)
    end

    test "apply_reverse_filtering works without source parameter" do
      @event.update!(sync_exempt: true)

      CalendarHub::EventFilter.apply_reverse_filtering

      refute_predicate(@event.reload, :sync_exempt?)
    end

    test "find_re_includable_events excludes events that still match rules" do
      @event.update!(sync_exempt: true)

      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
        calendar_source: @calendar_source,
      )

      # Event still matches rule, so should not be re-includable
      re_includable = CalendarHub::EventFilter.find_re_includable_events(@calendar_source)

      refute_includes(re_includable, @event)
    end

    test "apply_backwards_filtering returns zero when no events match" do
      @event.update!(sync_exempt: false)

      FilterRule.create!(
        pattern: "NonMatchingPattern",
        field_name: "title",
        match_type: "contains",
        active: true,
        calendar_source: @calendar_source,
      )

      filtered_count = CalendarHub::EventFilter.apply_backwards_filtering(@calendar_source)

      assert_equal(0, filtered_count)
      refute_predicate(@event.reload, :sync_exempt?)
    end
  end
end
