# frozen_string_literal: true

require "test_helper"

class RealtimeControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get "/realtime"

    assert_response :success
    refute_nil session[:realtime_token]
  end

  test "should get show with token from params" do
    token = "test123"
    get "/realtime", params: { token: token }

    assert_response :success
    assert_equal token, session[:realtime_token]
  end

  test "should get show with existing session token" do
    existing_token = "existing456"
    get "/realtime", params: { token: existing_token }

    assert_response :success

    get "/realtime"

    assert_response :success
    assert_equal existing_token, session[:realtime_token]
  end

  test "should get show with blank token param and use session" do
    existing_token = "existing789"
    get "/realtime", params: { token: existing_token }

    assert_response :success

    get "/realtime", params: { token: "" }

    assert_response :success
    assert_equal existing_token, session[:realtime_token]
  end

  test "should generate new token when none provided" do
    get "/realtime"

    assert_response :success
    refute_nil session[:realtime_token]
    assert_match(/^[a-f0-9]{12}$/, session[:realtime_token])
  end

  test "should handle ActionCable config variations" do
    get "/realtime"

    assert_response :success
    assert_select "h1", text: "Realtime Diagnostics"
  end

  # Test ActionCable adapter detection with different config scenarios
  test "should handle ActionCable config as hash with adapter key" do
    mock_config = { adapter: "redis" }
    ActionCable.server.config.expects(:cable).returns(mock_config).at_least_once

    get "/realtime"

    assert_response :success
    assert_includes response.body, "redis"
  end

  test "should handle ActionCable config as hash with string adapter key" do
    mock_config = { "adapter" => "postgresql" }
    ActionCable.server.config.expects(:cable).returns(mock_config).at_least_once

    get "/realtime"

    assert_response :success
    assert_includes response.body, "postgresql"
  end

  test "should handle ActionCable config as non-hash" do
    ActionCable.server.config.expects(:cable).returns("not_a_hash").at_least_once

    get "/realtime"

    assert_response :success
    assert_includes response.body, "unknown"
  end

  test "should handle ActionCable config exception" do
    ActionCable.server.config.expects(:cable).raises(StandardError.new("Config error")).at_least_once

    get "/realtime"

    assert_response :success
    assert_includes response.body, "unknown"
  end

  test "should handle ActionCable config with no adapter key" do
    mock_config = { other_key: "value" }
    ActionCable.server.config.expects(:cable).returns(mock_config).at_least_once

    get "/realtime"

    assert_response :success
    assert_includes response.body, "unknown"
  end

  test "should post ping with turbo_stream format" do
    token = "ping_test"

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream == "realtime_test_#{token}" &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time].is_a?(Time) &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", params: { token: token }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal token, session[:realtime_token]
  end

  test "should post ping with html format" do
    token = "ping_html_test"

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream == "realtime_test_#{token}" &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time].is_a?(Time) &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", params: { token: token }

    assert_redirected_to "/realtime?token=#{token}"
    assert_equal "Broadcast sent", flash[:notice]
    assert_equal token, session[:realtime_token]
  end

  test "should post ping without token and use existing session" do
    existing_token = "existing_ping"
    get "/realtime", params: { token: existing_token }

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream == "realtime_test_#{existing_token}" &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time].is_a?(Time) &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal existing_token, session[:realtime_token]
  end

  test "should post ping without token and generate new one" do
    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream.is_a?(String) &&
        stream.start_with?("realtime_test_") &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time].is_a?(Time) &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    refute_nil session[:realtime_token]
    assert_match(/^[a-f0-9]{12}$/, session[:realtime_token])
  end

  test "should use current time in ping broadcast" do
    token = "time_test"
    freeze_time = Time.parse("2025-01-01 12:00:00 UTC")

    Time.expects(:current).returns(freeze_time).at_least_once
    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream == "realtime_test_#{token}" &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time] == freeze_time &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", params: { token: token }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
  end

  test "should handle ping with blank token param" do
    existing_token = "blank_test"
    get "/realtime", params: { token: existing_token }

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with do |stream, options|
      stream == "realtime_test_#{existing_token}" &&
        options[:target] == "realtime_probe" &&
        options[:partial] == "realtime/payload" &&
        options[:locals][:time].is_a?(Time) &&
        options[:locals][:note] == "pong"
    end.once

    post "/realtime/ping", params: { token: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal existing_token, session[:realtime_token]
  end
end
