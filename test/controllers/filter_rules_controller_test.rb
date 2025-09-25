# frozen_string_literal: true

require "test_helper"

class FilterRulesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @filter_rule = FilterRule.create!(
      pattern: "Meeting",
      field_name: "title",
      match_type: "contains",
      active: true,
    )
    @calendar_source = calendar_sources(:provider)
  end

  test "should get index" do
    get filter_rules_url

    assert_response(:success)
    assert_select("h1", "Filter Rules")
  end

  test "should create filter rule" do
    assert_difference("FilterRule.count") do
      post filter_rules_url, params: {
        filter_rule: {
          pattern: "Standup",
          field_name: "title",
          match_type: "contains",
          active: true,
        },
      }
    end

    filter_rule = FilterRule.last

    assert_equal("Standup", filter_rule.pattern)
    assert_equal("title", filter_rule.field_name)
    assert_equal("contains", filter_rule.match_type)
    assert_predicate(filter_rule, :active?)
  end

  test "should update filter rule" do
    patch filter_rule_url(@filter_rule), params: {
      filter_rule: {
        pattern: "Updated Meeting",
        active: false,
      },
    }

    @filter_rule.reload

    assert_equal("Updated Meeting", @filter_rule.pattern)
    refute_predicate(@filter_rule, :active?)
  end

  test "should toggle filter rule" do
    original_active = @filter_rule.active?

    patch toggle_filter_rule_url(@filter_rule)

    @filter_rule.reload

    assert_equal(!original_active, @filter_rule.active?)
  end

  test "should destroy filter rule" do
    assert_difference("FilterRule.count", -1) do
      delete filter_rule_url(@filter_rule)
    end
  end

  test "should test filter rules" do
    post test_filter_rules_url,
      params: {
        sample_title: "Team Meeting",
        sample_description: "Weekly sync",
        sample_location: "Office",
      },
      as: :turbo_stream

    assert_response(:success)
  end

  test "should reorder filter rules" do
    rule2 = FilterRule.create!(
      pattern: "Standup",
      field_name: "title",
      match_type: "contains",
      position: 1,
    )

    post reorder_filter_rules_url, params: {
      order: [rule2.id, @filter_rule.id],
    }

    assert_response(:success)

    @filter_rule.reload
    rule2.reload

    assert_equal(1, @filter_rule.position)
    assert_equal(0, rule2.position)
  end

  test "should validate required fields" do
    post filter_rules_url, params: {
      filter_rule: {
        pattern: "",
        field_name: "title",
        match_type: "contains",
      },
    }

    assert_response(:unprocessable_entity)
  end

  test "should validate match_type inclusion" do
    assert_raises(ArgumentError) do
      post filter_rules_url, params: {
        filter_rule: {
          pattern: "test",
          field_name: "title",
          match_type: "invalid",
        },
      }
    end
  end

  test "should validate field_name inclusion" do
    assert_raises(ArgumentError) do
      post filter_rules_url, params: {
        filter_rule: {
          pattern: "test",
          field_name: "invalid",
          match_type: "contains",
        },
      }
    end
  end
end
