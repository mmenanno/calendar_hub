# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class EventFilterTest < ActiveSupport::TestCase
    def setup
      @calendar_source = calendar_sources(:provider)
      @event = calendar_events(:provider_consult)
      @event.update!(title: "Team Meeting", description: "Weekly sync", location: "Conference Room A")
    end

    test "should_filter? returns false when no rules match" do
      refute(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? returns true when rule matches" do
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
      )

      assert(CalendarHub::EventFilter.should_filter?(@event))
    end

    test "should_filter? respects calendar source scoping" do
      other_source = CalendarSource.create!(
        name: "Other Source",
        calendar_identifier: "other-cal",
        ingestion_url: "https://example.com/other.ics",
      )

      # Rule for specific source
      FilterRule.create!(
        pattern: "Meeting",
        field_name: "title",
        match_type: "contains",
        active: true,
        calendar_source: other_source,
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

      # No rules, so event should be re-included
      re_included_count = CalendarHub::EventFilter.apply_reverse_filtering(@calendar_source)

      assert_equal(1, re_included_count)
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
  end
end
