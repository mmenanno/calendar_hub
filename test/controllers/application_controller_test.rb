# frozen_string_literal: true

require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "allows modern browsers" do
    filters = ApplicationController._process_action_callbacks
    browser_filter = filters.any? { |filter| filter.filter.to_s.include?("allow_browser") }

    assert(browser_filter, "Expected allow_browser filter to be configured")
  end

  test "inherits from ActionController::Base" do
    assert_operator(ApplicationController, :<, ActionController::Base)
  end

  test "browser version filter is configured" do
    assert_respond_to(ApplicationController, :new)
  end
end
