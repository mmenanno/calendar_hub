# frozen_string_literal: true

require "test_helper"

class FilterRuleTest < ActiveSupport::TestCase
  def setup
    @calendar_source = calendar_sources(:provider)
    @event = calendar_events(:provider_consult)
  end

  test "should be valid with required attributes" do
    filter_rule = FilterRule.new(
      pattern: "Team Meeting",
      field_name: "title",
      match_type: "contains",
    )

    assert_predicate(filter_rule, :valid?)
  end

  test "should require pattern" do
    filter_rule = FilterRule.new(field_name: "title", match_type: "contains")

    refute_predicate(filter_rule, :valid?)
    assert_includes(filter_rule.errors[:pattern], "can't be blank")
  end

  test "should validate match_type inclusion" do
    assert_raises(ArgumentError) do
      FilterRule.new(
        pattern: "test",
        field_name: "title",
        match_type: "invalid",
      )
    end
  end

  test "should validate field_name inclusion" do
    assert_raises(ArgumentError) do
      FilterRule.new(
        pattern: "test",
        field_name: "invalid",
        match_type: "contains",
      )
    end
  end

  test "should match event with contains match_type" do
    filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
      case_sensitive: false,
    )

    event = CalendarEvent.new(title: "Team Meeting", description: "Weekly sync", location: "Office")

    assert(filter_rule.matches?(event))

    event.title = "Daily Standup"

    refute(filter_rule.matches?(event))
  end

  test "should match event with equals match_type" do
    filter_rule = FilterRule.create!(
      pattern: "Team Meeting",
      field_name: "title",
      match_type: "equals",
      case_sensitive: false,
    )

    event = CalendarEvent.new(title: "Team Meeting", description: "Weekly sync", location: "Office")

    assert(filter_rule.matches?(event))

    event.title = "team meeting"

    assert(filter_rule.matches?(event)) # case insensitive

    event.title = "Team Meeting Notes"

    refute(filter_rule.matches?(event))
  end

  test "should match event with regex match_type" do
    filter_rule = FilterRule.create!(
      pattern: "^Team.*Meeting$",
      field_name: "title",
      match_type: "regex",
      case_sensitive: false,
    )

    event = CalendarEvent.new(title: "Team Weekly Meeting", description: "Weekly sync", location: "Office")

    assert(filter_rule.matches?(event))

    event.title = "Daily Team Meeting"

    refute(filter_rule.matches?(event))
  end

  test "should handle case sensitivity" do
    filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
      case_sensitive: true,
    )

    event = CalendarEvent.new(title: "Team Meeting", description: "Weekly sync", location: "Office")

    assert(filter_rule.matches?(event))

    event.title = "Team meeting"

    refute(filter_rule.matches?(event))
  end

  test "should match different fields" do
    title_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
    )

    description_rule = FilterRule.create!(
      pattern: "standup",
      field_name: "description",
      match_type: "contains",
    )

    location_rule = FilterRule.create!(
      pattern: "Office",
      field_name: "location",
      match_type: "contains",
    )

    event = CalendarEvent.new(
      title: "Team Meeting",
      description: "Daily standup session",
      location: "Office A",
    )

    assert(title_rule.matches?(event))
    assert(description_rule.matches?(event))
    assert(location_rule.matches?(event))
  end

  test "should not match blank fields" do
    filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
    )

    event = CalendarEvent.new(title: "", description: "Weekly sync", location: "Office")

    refute(filter_rule.matches?(event))

    event.title = nil

    refute(filter_rule.matches?(event))
  end

  test "should handle invalid regex gracefully" do
    filter_rule = FilterRule.create!(
      pattern: "[invalid regex",
      field_name: "title",
      match_type: "regex",
    )

    event = CalendarEvent.new(title: "Team Meeting", description: "Weekly sync", location: "Office")

    refute(filter_rule.matches?(event))
  end

  test "should not match inactive rules" do
    filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
      active: false,
    )

    event = CalendarEvent.new(title: "Team Meeting", description: "Weekly sync", location: "Office")

    refute(filter_rule.matches?(event))
  end

  test "should belong to calendar_source optionally" do
    filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
      calendar_source: @calendar_source,
    )

    assert_equal(@calendar_source, filter_rule.calendar_source)

    # Should also work without calendar_source (global rule)
    global_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
    )

    assert_nil(global_rule.calendar_source)
  end
end
