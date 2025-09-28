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
    initial_count = FilterRule.count

    post filter_rules_url, params: {
      filter_rule: {
        pattern: "Standup",
        field_name: "title",
        match_type: "contains",
        active: true,
      },
    }

    assert_equal(initial_count + 1, FilterRule.count)

    filter_rule = FilterRule.find_by(pattern: "Standup", field_name: "title", match_type: "contains")

    refute_nil(filter_rule)
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

  test "should duplicate filter rule" do
    assert_difference("FilterRule.count") do
      post duplicate_filter_rule_url(@filter_rule), as: :turbo_stream
    end

    copy = FilterRule.order(:created_at).last

    assert_equal(@filter_rule.pattern, copy.pattern)
    assert_equal(@filter_rule.field_name, copy.field_name)
    assert_equal(@filter_rule.match_type, copy.match_type)
  end

  test "should not run filter test when no inputs provided" do
    post test_filter_rules_url,
      params: { sample_title: "", sample_description: "", sample_location: "" },
      as: :turbo_stream

    assert_response(:success)
  end

  # Test turbo_stream responses
  test "should create filter rule with turbo_stream" do
    assert_difference("FilterRule.count") do
      post filter_rules_url,
        params: {
          filter_rule: {
            pattern: "Standup",
            field_name: "title",
            match_type: "contains",
            active: true,
          },
        },
        as: :turbo_stream
    end

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")
  end

  test "should create filter rule with calendar_source and sync filters" do
    assert_difference("FilterRule.count") do
      post filter_rules_url,
        params: {
          filter_rule: {
            pattern: "Meeting",
            field_name: "title",
            match_type: "contains",
            active: true,
            calendar_source_id: @calendar_source.id,
          },
        },
        as: :turbo_stream
    end

    filter_rule = FilterRule.find_by(pattern: "Meeting", field_name: "title", match_type: "contains", calendar_source_id: @calendar_source.id)

    refute_nil(filter_rule)
    assert_equal(@calendar_source.id, filter_rule.calendar_source_id)
    assert_response(:success)
  end

  test "should handle create filter rule validation errors with turbo_stream" do
    post filter_rules_url,
      params: {
        filter_rule: {
          pattern: "", # invalid - blank pattern
          field_name: "title",
          match_type: "contains",
        },
      },
      as: :turbo_stream

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")
  end

  test "should handle create filter rule validation errors with html" do
    post filter_rules_url, params: {
      filter_rule: {
        pattern: "", # invalid - blank pattern
        field_name: "title",
        match_type: "contains",
      },
    }

    assert_response(:unprocessable_entity)
  end

  test "should update filter rule with turbo_stream" do
    patch filter_rule_url(@filter_rule),
      params: {
        filter_rule: {
          pattern: "Updated Meeting",
          active: false,
        },
      },
      as: :turbo_stream

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")

    @filter_rule.reload

    assert_equal("Updated Meeting", @filter_rule.pattern)
    refute_predicate(@filter_rule, :active?)
  end

  test "should handle update filter rule validation errors with turbo_stream" do
    patch filter_rule_url(@filter_rule),
      params: {
        filter_rule: {
          pattern: "", # invalid - blank pattern
        },
      },
      as: :turbo_stream

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")
  end

  test "should handle update filter rule validation errors with html" do
    patch filter_rule_url(@filter_rule), params: {
      filter_rule: {
        pattern: "", # invalid - blank pattern
      },
    }

    assert_response(:unprocessable_entity)
  end

  test "should toggle filter rule with turbo_stream" do
    original_active = @filter_rule.active?

    patch toggle_filter_rule_url(@filter_rule), as: :turbo_stream

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")

    @filter_rule.reload

    assert_equal(!original_active, @filter_rule.active?)
  end

  test "should toggle filter rule with html" do
    original_active = @filter_rule.active?

    patch toggle_filter_rule_url(@filter_rule)

    assert_redirected_to(filter_rules_path)

    @filter_rule.reload

    assert_equal(!original_active, @filter_rule.active?)
  end

  test "should destroy filter rule with turbo_stream" do
    assert_difference("FilterRule.count", -1) do
      delete filter_rule_url(@filter_rule), as: :turbo_stream
    end

    assert_response(:success)
    assert_includes(response.body, "turbo-stream")
  end

  test "should destroy filter rule with html" do
    assert_difference("FilterRule.count", -1) do
      delete filter_rule_url(@filter_rule)
    end

    assert_redirected_to(filter_rules_path)
  end

  test "should destroy filter rule with calendar_source and sync filters" do
    filter_rule_with_source = FilterRule.create!(
      pattern: "Test",
      field_name: "title",
      match_type: "contains",
      calendar_source: @calendar_source,
    )

    assert_difference("FilterRule.count", -1) do
      delete filter_rule_url(filter_rule_with_source), as: :turbo_stream
    end

    assert_response(:success)
  end

  test "should duplicate filter rule with html" do
    assert_difference("FilterRule.count") do
      post duplicate_filter_rule_url(@filter_rule)
    end

    assert_redirected_to(filter_rules_path)
  end

  test "should get edit" do
    get edit_filter_rule_url(@filter_rule)

    assert_response(:success)
    assert_select("form")
  end

  test "should test filter rules with calendar_source" do
    post test_filter_rules_url,
      params: {
        sample_title: "Team Meeting",
        sample_description: "Weekly sync",
        sample_location: "Office",
        calendar_source_id: @calendar_source.id,
      },
      as: :turbo_stream

    assert_response(:success)
  end

  test "should test filter rules with empty calendar_source_id" do
    post test_filter_rules_url,
      params: {
        sample_title: "Team Meeting",
        sample_description: "Weekly sync",
        sample_location: "Office",
        calendar_source_id: "",
      },
      as: :turbo_stream

    assert_response(:success)
  end

  test "should test filter rules with invalid calendar_source_id" do
    post test_filter_rules_url,
      params: {
        sample_title: "Team Meeting",
        sample_description: "Weekly sync",
        sample_location: "Office",
        calendar_source_id: "999999",
      },
      as: :turbo_stream

    assert_response(:success)
  end

  test "should reorder filter rules with invalid ids" do
    post reorder_filter_rules_url, params: {
      order: ["999999", "888888"],
    }

    assert_response(:success)
  end

  test "should reorder filter rules with mixed valid and invalid ids" do
    rule2 = FilterRule.create!(
      pattern: "Standup",
      field_name: "title",
      match_type: "contains",
      position: 1,
    )

    # Before reordering, let's check initial positions
    # @filter_rule was created in setup, rule2 was created here
    # The controller processes each ID and assigns position based on array index:
    # - rule2.id is at index 0, so it gets position 0
    # - "999999" is at index 1 but invalid, so skipped
    # - @filter_rule.id is at index 2, so it gets position 2

    post reorder_filter_rules_url, params: {
      order: [rule2.id, "999999", @filter_rule.id],
    }

    assert_response(:success)

    @filter_rule.reload
    rule2.reload

    assert_equal(2, @filter_rule.position) # Gets position 2 (index in array)
    assert_equal(0, rule2.position) # Gets position 0 (index in array)
  end

  test "should reorder filter rules with empty order array" do
    post reorder_filter_rules_url, params: { order: [] }

    assert_response(:success)
  end

  test "should reorder filter rules with no order param" do
    post reorder_filter_rules_url

    assert_response(:success)
  end

  test "should create filter rule without calendar_source and sync all active sources" do
    # Create another active calendar source
    CalendarSource.create!(
      name: "Source 2",
      ingestion_url: "https://example.com/source2.ics",
      calendar_identifier: "source2",
      active: true,
    )

    assert_difference("FilterRule.count") do
      post filter_rules_url,
        params: {
          filter_rule: {
            pattern: "Global Rule",
            field_name: "title",
            match_type: "contains",
            active: true,
          },
        },
        as: :turbo_stream
    end

    assert_response(:success)

    filter_rule = FilterRule.find_by(pattern: "Global Rule", field_name: "title", match_type: "contains")

    refute_nil(filter_rule)
    assert_nil(filter_rule.calendar_source_id)
  end

  test "should destroy filter rule without calendar_source and sync all active sources" do
    # Create a filter rule without calendar_source
    global_rule = FilterRule.create!(
      pattern: "Global Rule",
      field_name: "title",
      match_type: "contains",
      active: true,
    )

    # Create another active calendar source
    CalendarSource.create!(
      name: "Source 2",
      ingestion_url: "https://example.com/source2.ics",
      calendar_identifier: "source2",
      active: true,
    )

    assert_difference("FilterRule.count", -1) do
      delete filter_rule_url(global_rule), as: :turbo_stream
    end

    assert_response(:success)
  end

  test "should handle create with HTML format success" do
    assert_difference("FilterRule.count") do
      post filter_rules_url, params: {
        filter_rule: {
          pattern: "HTML Test",
          field_name: "title",
          match_type: "contains",
          active: true,
        },
      }
    end

    assert_redirected_to(filter_rules_path)
    follow_redirect!

    assert_response(:success)
  end

  test "should handle update with HTML format success" do
    patch filter_rule_url(@filter_rule), params: {
      filter_rule: {
        pattern: "Updated via HTML",
        active: false,
      },
    }

    assert_redirected_to(filter_rules_path)
    follow_redirect!

    assert_response(:success)

    @filter_rule.reload

    assert_equal("Updated via HTML", @filter_rule.pattern)
    refute_predicate(@filter_rule, :active?)
  end

  test "should handle edit action with specific filter rule" do
    get edit_filter_rule_url(@filter_rule)

    assert_response(:success)
    assert_select("form")
    assert_select("input[value='#{@filter_rule.pattern}']")
  end

  test "should test filter rules with all empty parameters" do
    post test_filter_rules_url,
      params: {},
      as: :turbo_stream

    assert_response(:success)
  end

  test "should reorder with string IDs (simulating form submission)" do
    rule2 = FilterRule.create!(
      pattern: "String ID Test",
      field_name: "title",
      match_type: "contains",
      position: 1,
    )

    # Simulate form submission with string IDs
    post reorder_filter_rules_url, params: {
      order: [rule2.id.to_s, @filter_rule.id.to_s],
    }

    assert_response(:success)

    @filter_rule.reload
    rule2.reload

    assert_equal(1, @filter_rule.position)
    assert_equal(0, rule2.position)
  end

  test "should handle duplicate with maximum position calculation" do
    # Create a rule with a high position to test the maximum calculation
    FilterRule.create!(
      pattern: "High Position",
      field_name: "title",
      match_type: "contains",
      position: 999,
    )

    assert_difference("FilterRule.count") do
      post duplicate_filter_rule_url(@filter_rule), as: :turbo_stream
    end

    copy = FilterRule.order(:created_at).last
    # The copy should get position 1000 (999 + 1)
    assert_equal(1000, copy.position)
    assert_response(:success)
  end

  test "should create filter rule with all supported parameters" do
    assert_difference("FilterRule.count") do
      post filter_rules_url,
        params: {
          filter_rule: {
            pattern: "Complete Test",
            field_name: "description",
            match_type: "regex",
            active: false,
            case_sensitive: true,
            position: 5,
            calendar_source_id: @calendar_source.id,
          },
        },
        as: :turbo_stream
    end

    assert_response(:success)
  end

  test "should set all parameters correctly when creating filter rule" do
    post filter_rules_url,
      params: {
        filter_rule: {
          pattern: "Complete Test",
          field_name: "description",
          match_type: "regex",
          active: false,
          case_sensitive: true,
          position: 5,
          calendar_source_id: @calendar_source.id,
        },
      },
      as: :turbo_stream

    filter_rule = FilterRule.find_by(pattern: "Complete Test", field_name: "description", match_type: "regex")

    refute_nil(filter_rule)
    assert_equal("Complete Test", filter_rule.pattern)
    assert_equal("description", filter_rule.field_name)
    assert_equal("regex", filter_rule.match_type)
    refute_predicate(filter_rule, :active?)
    assert_predicate(filter_rule, :case_sensitive?)
    assert_equal([@calendar_source.id, 5], [filter_rule.calendar_source_id, filter_rule.position])
  end

  test "should update filter rule with all supported parameters" do
    patch filter_rule_url(@filter_rule),
      params: {
        filter_rule: {
          pattern: "Updated Complete",
          field_name: "location",
          match_type: "equals",
          active: false,
          case_sensitive: false,
          position: 10,
          calendar_source_id: @calendar_source.id,
        },
      },
      as: :turbo_stream

    assert_response(:success)
  end

  test "should set all parameters correctly when updating filter rule" do
    patch filter_rule_url(@filter_rule),
      params: {
        filter_rule: {
          pattern: "Updated Complete",
          field_name: "location",
          match_type: "equals",
          active: false,
          case_sensitive: false,
          position: 10,
          calendar_source_id: @calendar_source.id,
        },
      },
      as: :turbo_stream

    @filter_rule.reload

    assert_equal("Updated Complete", @filter_rule.pattern)
    assert_equal("location", @filter_rule.field_name)
    assert_equal("equals", @filter_rule.match_type)
    refute_predicate(@filter_rule, :active?)
    refute_predicate(@filter_rule, :case_sensitive?)
    assert_equal(10, @filter_rule.position)
    assert_equal(@calendar_source.id, @filter_rule.calendar_source_id)
  end

  test "should duplicate filter rule when no existing rules have positions" do
    # Delete all existing filter rules to test the case where maximum position is nil
    FilterRule.delete_all

    # Create a new filter rule without position
    new_rule = FilterRule.create!(
      pattern: "No Position Rule",
      field_name: "title",
      match_type: "contains",
      active: true,
    )

    assert_difference("FilterRule.count") do
      post duplicate_filter_rule_url(new_rule), as: :turbo_stream
    end

    copy = FilterRule.order(:created_at).last
    # When maximum position is nil, to_i returns 0, so copy should get position 1
    assert_equal(1, copy.position)
    assert_response(:success)
  end

  test "should handle reorder with non-integer values" do
    rule2 = FilterRule.create!(
      pattern: "Non Integer Test",
      field_name: "title",
      match_type: "contains",
      position: 1,
    )

    # Test with various non-integer values that to_i will convert
    post reorder_filter_rules_url, params: {
      order: ["#{rule2.id}abc", "#{@filter_rule.id}.5", "invalid", nil],
    }

    assert_response(:success)

    @filter_rule.reload
    rule2.reload

    # The to_i conversion should still work for valid numeric prefixes
    assert_equal(1, @filter_rule.position)
    assert_equal(0, rule2.position)
  end
end
