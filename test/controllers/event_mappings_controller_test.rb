# frozen_string_literal: true

require "test_helper"

class EventMappingsControllerTest < ActionDispatch::IntegrationTest
  test "index displays mappings ordered by position and created_at" do
    get event_mappings_path

    assert_response :success

    assert_select "body"
  end

  test "reorder updates positions correctly" do
    mapping1 = event_mappings(:basic_mapping)
    mapping2 = event_mappings(:regex_mapping)
    mapping3 = event_mappings(:global_mapping)

    post reorder_event_mappings_path, params: { order: [mapping3.id, mapping1.id, mapping2.id] }

    assert_response :ok

    mapping1.reload
    mapping2.reload
    mapping3.reload

    assert_equal 1, mapping1.position
    assert_equal 2, mapping2.position
    assert_equal 0, mapping3.position
  end

  test "reorder handles invalid ids gracefully" do
    mapping1 = event_mappings(:basic_mapping)

    post reorder_event_mappings_path, params: { order: [mapping1.id, 99999, "invalid"] }

    assert_response :ok

    mapping1.reload

    assert_equal 0, mapping1.position
  end

  test "reorder handles empty array" do
    post reorder_event_mappings_path, params: { order: [] }

    assert_response :ok
  end

  test "reorder handles nil params" do
    post reorder_event_mappings_path

    assert_response :ok
  end

  test "toggle activates inactive mapping with turbo_stream" do
    mapping = event_mappings(:inactive_mapping)

    refute_predicate mapping, :active?

    patch toggle_event_mapping_path(mapping),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping enabled", response.body

    mapping.reload

    assert_predicate mapping, :active?
  end

  test "toggle deactivates active mapping with turbo_stream" do
    mapping = event_mappings(:basic_mapping)

    assert_predicate mapping, :active?

    patch toggle_event_mapping_path(mapping),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping disabled", response.body

    mapping.reload

    refute_predicate mapping, :active?
  end

  test "toggle with html format redirects" do
    mapping = event_mappings(:basic_mapping)

    patch toggle_event_mapping_path(mapping)

    assert_redirected_to event_mappings_path

    mapping.reload

    refute_predicate mapping, :active?
  end

  test "toggle with non-existent mapping returns 404" do
    patch(toggle_event_mapping_path(99999))

    assert_response(:not_found)
  end

  test "test action applies name mapping with source" do
    source = calendar_sources(:provider)

    post test_event_mappings_path,
      params: {
        sample_title: "Team Meeting Today",
        calendar_source_id: source.id,
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "mapping_test_result", response.body
  end

  test "test action applies name mapping without source" do
    post test_event_mappings_path,
      params: { sample_title: "Daily Standup" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "mapping_test_result", response.body
  end

  test "test action handles empty sample title" do
    post test_event_mappings_path,
      params: { sample_title: "" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "test action handles missing sample title" do
    post test_event_mappings_path,
      params: {},
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "test action handles invalid calendar source id" do
    post test_event_mappings_path,
      params: {
        sample_title: "Test",
        calendar_source_id: 99999,
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "test action handles blank calendar source id" do
    post test_event_mappings_path,
      params: {
        sample_title: "Test",
        calendar_source_id: "",
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "edit loads mapping" do
    mapping = event_mappings(:basic_mapping)

    get edit_event_mapping_path(mapping)

    assert_response :success
    assert_select "body"
  end

  test "edit with non-existent mapping returns 404" do
    get(edit_event_mapping_path(99999))

    assert_response(:not_found)
  end

  test "create with valid params and turbo_stream format" do
    valid_params = {
      event_mapping: {
        calendar_source_id: calendar_sources(:provider).id,
        match_type: "contains",
        pattern: "New Pattern",
        replacement: "New Replacement",
        case_sensitive: false,
        active: true,
      },
    }

    assert_difference("EventMapping.count") do
      post event_mappings_path,
        params: valid_params,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping added", response.body

    created_mapping = EventMapping.find_by(pattern: "New Pattern", replacement: "New Replacement")

    refute_nil created_mapping
    assert_equal "New Pattern", created_mapping.pattern
    assert_equal "New Replacement", created_mapping.replacement
  end

  test "create with valid params and html format" do
    valid_params = {
      event_mapping: {
        match_type: "equals",
        pattern: "HTML Pattern",
        replacement: "HTML Replacement",
        case_sensitive: true,
      },
    }

    assert_difference("EventMapping.count") do
      post event_mappings_path, params: valid_params
    end

    assert_redirected_to event_mappings_path
    follow_redirect!

    assert_match "Mapping added", flash[:notice]
  end

  test "create with invalid params and turbo_stream format" do
    invalid_params = {
      event_mapping: {
        match_type: "contains",
        pattern: "",
        replacement: "Some replacement",
      },
    }

    assert_no_difference("EventMapping.count") do
      post event_mappings_path,
        params: invalid_params,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :unprocessable_entity
    assert_match "turbo-stream", response.body
  end

  test "create with invalid params and html format" do
    invalid_params = {
      event_mapping: {
        match_type: "contains",
        pattern: "Some pattern",
        replacement: "",
      },
    }

    assert_no_difference("EventMapping.count") do
      post event_mappings_path, params: invalid_params
    end

    assert_redirected_to event_mappings_path
    follow_redirect!

    refute_nil flash[:alert]
  end

  test "update with valid params and turbo_stream format" do
    mapping = event_mappings(:basic_mapping)

    patch event_mapping_path(mapping),
      params: {
        event_mapping: {
          pattern: "Updated Pattern",
          replacement: "Updated Replacement",
        },
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping saved", response.body

    mapping.reload

    assert_equal "Updated Pattern", mapping.pattern
    assert_equal "Updated Replacement", mapping.replacement
  end

  test "update with valid params and html format" do
    mapping = event_mappings(:basic_mapping)

    patch event_mapping_path(mapping),
      params: {
        event_mapping: {
          pattern: "HTML Updated Pattern",
        },
      }

    assert_redirected_to event_mappings_path

    mapping.reload

    assert_equal "HTML Updated Pattern", mapping.pattern
  end

  test "update with invalid params returns unprocessable entity" do
    mapping = event_mappings(:basic_mapping)

    patch event_mapping_path(mapping),
      params: {
        event_mapping: {
          pattern: "",
          replacement: "",
        },
      }

    assert_response :unprocessable_entity

    mapping.reload

    refute_equal "", mapping.pattern
  end

  test "update with non-existent mapping returns 404" do
    patch(
      event_mapping_path(99999),
      params: { event_mapping: { pattern: "Test" } },
    )

    assert_response(:not_found)
  end

  test "duplicate creates copy with turbo_stream format" do
    original = event_mappings(:basic_mapping)

    assert_difference("EventMapping.count") do
      post duplicate_event_mapping_path(original),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping duplicated", response.body
  end

  test "duplicate creates exact copy with correct attributes" do
    original = event_mappings(:basic_mapping)

    post duplicate_event_mapping_path(original),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    duplicate = EventMapping.order(:created_at).last

    assert_equal original.pattern, duplicate.pattern
    assert_equal original.replacement, duplicate.replacement
    assert_equal original.match_type, duplicate.match_type
    assert_equal original.case_sensitive, duplicate.case_sensitive
    refute_equal original.id, duplicate.id
  end

  test "duplicate sets correct position" do
    original = event_mappings(:basic_mapping)

    post duplicate_event_mapping_path(original),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    duplicate = EventMapping.order(:created_at).last
    max_position = EventMapping.where.not(id: duplicate.id).maximum(:position) || 0

    assert_equal max_position + 1, duplicate.position
  end

  test "duplicate creates copy with html format" do
    original = event_mappings(:regex_mapping)

    assert_difference("EventMapping.count") do
      post duplicate_event_mapping_path(original)
    end

    assert_redirected_to event_mappings_path
    follow_redirect!

    assert_match "Mapping duplicated", flash[:notice]
  end

  test "duplicate with non-existent mapping returns 404" do
    post(duplicate_event_mapping_path(99999))

    assert_response(:not_found)
  end

  test "destroy removes mapping with turbo_stream format" do
    mapping = event_mappings(:basic_mapping)

    assert_difference("EventMapping.count", -1) do
      delete event_mapping_path(mapping),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "Mapping removed", response.body
  end

  test "destroy removes mapping with html format" do
    mapping = event_mappings(:regex_mapping)

    assert_difference("EventMapping.count", -1) do
      delete event_mapping_path(mapping)
    end

    assert_redirected_to event_mappings_path
    follow_redirect!

    assert_match "Mapping removed", flash[:notice]
  end

  test "destroy with non-existent mapping returns 404" do
    delete(event_mapping_path(99999))

    assert_response(:not_found)
  end

  test "set_mapping before_action works correctly" do
    mapping = event_mappings(:basic_mapping)

    delete event_mapping_path(mapping),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
  end

  test "event_mapping_params filters correctly" do
    params_with_extra = {
      event_mapping: {
        match_type: "contains",
        pattern: "Test Pattern",
        replacement: "Test Replacement",
        case_sensitive: false,
        position: 5,
        active: true,
        id: 123,
        created_at: Time.current,
        updated_at: Time.current,
        malicious_param: "hack",
      },
    }

    assert_difference("EventMapping.count") do
      post event_mappings_path, params: params_with_extra
    end

    created_mapping = EventMapping.find_by(pattern: "Test Pattern", replacement: "Test Replacement")

    refute_nil created_mapping
  end

  test "event_mapping_params allows permitted attributes" do
    params_with_extra = {
      event_mapping: {
        match_type: "contains",
        pattern: "Test Pattern",
        replacement: "Test Replacement",
        case_sensitive: false,
        position: 5,
        active: true,
      },
    }

    post event_mappings_path, params: params_with_extra
    created_mapping = EventMapping.find_by(pattern: "Test Pattern", replacement: "Test Replacement")

    assert_equal "Test Pattern", created_mapping.pattern
    assert_equal "Test Replacement", created_mapping.replacement
    assert_equal "contains", created_mapping.match_type
    refute created_mapping.case_sensitive
    assert_equal 5, created_mapping.position
    assert_predicate created_mapping, :active?
  end

  test "event_mapping_params filters malicious attributes" do
    params_with_extra = {
      event_mapping: {
        match_type: "contains",
        pattern: "Test Pattern",
        replacement: "Test Replacement",
        id: 123,
        malicious_param: "hack",
      },
    }

    post event_mappings_path, params: params_with_extra
    created_mapping = EventMapping.find_by(pattern: "Test Pattern", replacement: "Test Replacement")

    refute_equal 123, created_mapping.id
  end

  test "reorder uses transaction" do
    mapping1 = event_mappings(:basic_mapping)
    mapping2 = event_mappings(:regex_mapping)

    original_pos1 = mapping1.position
    original_pos2 = mapping2.position

    post reorder_event_mappings_path, params: { order: [mapping2.id, mapping1.id] }

    assert_response :ok

    mapping1.reload
    mapping2.reload

    refute_equal original_pos1, mapping1.position
    refute_equal original_pos2, mapping2.position
  end

  test "create handles nil calendar_source_id" do
    valid_params = {
      event_mapping: {
        calendar_source_id: nil,
        match_type: "contains",
        pattern: "Global Pattern",
        replacement: "Global Replacement",
      },
    }

    assert_difference("EventMapping.count") do
      post event_mappings_path, params: valid_params
    end

    created_mapping = EventMapping.find_by(pattern: "Global Pattern", replacement: "Global Replacement")

    refute_nil created_mapping
    assert_equal "Global Pattern", created_mapping.pattern
  end

  test "update handles all permitted parameters" do
    mapping = event_mappings(:basic_mapping)
    source = calendar_sources(:ics_feed)

    patch event_mapping_path(mapping),
      params: {
        event_mapping: {
          calendar_source_id: source.id,
          match_type: "regex",
          pattern: "New.*Pattern",
          replacement: "New Replacement",
          case_sensitive: true,
          position: 10,
          active: false,
        },
      }

    assert_redirected_to event_mappings_path
  end

  test "update modifies all mapping attributes correctly" do
    mapping = event_mappings(:basic_mapping)
    source = calendar_sources(:ics_feed)

    patch event_mapping_path(mapping),
      params: {
        event_mapping: {
          calendar_source_id: source.id,
          match_type: "regex",
          pattern: "New.*Pattern",
          replacement: "New Replacement",
          case_sensitive: true,
          position: 10,
          active: false,
        },
      }

    mapping.reload

    assert_equal source.id, mapping.calendar_source_id
    assert_equal "regex", mapping.match_type
    assert_equal "New.*Pattern", mapping.pattern
    assert_equal "New Replacement", mapping.replacement
    assert_predicate mapping, :case_sensitive?
    assert_equal 10, mapping.position
    refute_predicate mapping, :active?
  end

  test "test action integrates with NameMapper service" do
    CalendarHub::NameMapper.expects(:apply).with("Test Title", source: nil).returns("Mapped Title")

    post test_event_mappings_path,
      params: { sample_title: "Test Title" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "mapping_test_result", response.body
  end

  test "test action integrates with NameMapper service with source" do
    source = calendar_sources(:provider)
    CalendarHub::NameMapper.expects(:apply).with("Test Title", source: source).returns("Source Mapped Title")

    post test_event_mappings_path,
      params: {
        sample_title: "Test Title",
        calendar_source_id: source.id,
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "mapping_test_result", response.body
  end
end
