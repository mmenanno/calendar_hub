# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @app_setting = AppSetting.instance
  end

  test "should get show" do
    get settings_path

    assert_response(:success)
  end

  test "should get edit" do
    get edit_settings_path

    assert_response(:success)
  end

  test "should update settings successfully" do
    patch settings_path, params: {
      app_setting: {
        default_time_zone: "America/New_York",
        default_calendar_identifier: "Work",
        notes: "Test notes",
      },
    }

    assert_redirected_to(edit_settings_path)
    assert_equal("Settings saved.", flash[:notice])

    @app_setting.reload

    assert_equal("America/New_York", @app_setting.default_time_zone)
    assert_equal("Work", @app_setting.default_calendar_identifier)
    assert_equal("Test notes", @app_setting.notes)
  end

  test "should update base url settings" do
    patch settings_path, params: {
      app_setting: {
        app_host: "example.com",
        app_protocol: "https",
        app_port: "443",
      },
    }

    assert_redirected_to(edit_settings_path)
    @app_setting.reload

    assert_equal("example.com", @app_setting.app_host)
    assert_equal("https", @app_setting.app_protocol)
    assert_equal("443", @app_setting.app_port.to_s)
  end

  test "should update apple credentials" do
    patch settings_path, params: {
      app_setting: {
        apple_username: "user@example.com",
        apple_app_password: "password123",
        default_sync_frequency_minutes: "120",
      },
    }

    assert_redirected_to(edit_settings_path)
    @app_setting.reload

    assert_equal("user@example.com", @app_setting.apple_username)
    assert_equal("password123", @app_setting.apple_app_password)
    assert_equal(120, @app_setting.default_sync_frequency_minutes)
  end

  test "should update settings with turbo_stream format" do
    patch settings_path,
      params: {
        app_setting: { default_time_zone: "America/Chicago" },
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)

    @app_setting.reload

    assert_equal("America/Chicago", @app_setting.default_time_zone)
  end

  test "should strip whitespace from string fields" do
    patch settings_path, params: {
      app_setting: {
        app_host: "  example.com  ",
        apple_username: "  user@example.com  ",
      },
    }

    assert_redirected_to(edit_settings_path)

    @app_setting.reload

    assert_equal("example.com", @app_setting.app_host)
    assert_equal("user@example.com", @app_setting.apple_username)
  end

  test "should preserve existing apple_app_password when blank" do
    @app_setting.update!(apple_app_password: "existing_password")

    patch settings_path, params: {
      app_setting: {
        apple_username: "user@example.com",
        apple_app_password: "",
      },
    }

    assert_redirected_to(edit_settings_path)

    @app_setting.reload

    assert_equal("user@example.com", @app_setting.apple_username)
    assert_equal("existing_password", @app_setting.apple_app_password)
  end

  test "should preserve existing apple_app_password when whitespace only" do
    @app_setting.update!(apple_app_password: "existing_password")

    patch settings_path, params: {
      app_setting: {
        apple_username: "user@example.com",
        apple_app_password: "   ",
      },
    }

    assert_redirected_to(edit_settings_path)

    @app_setting.reload

    assert_equal("user@example.com", @app_setting.apple_username)
    assert_equal("existing_password", @app_setting.apple_app_password)
  end

  test "should update apple_app_password when provided" do
    @app_setting.update!(apple_app_password: "existing_password")

    patch settings_path, params: {
      app_setting: {
        apple_username: "user@example.com",
        apple_app_password: "new_password",
      },
    }

    assert_redirected_to(edit_settings_path)

    @app_setting.reload

    assert_equal("user@example.com", @app_setting.apple_username)
    assert_equal("new_password", @app_setting.apple_app_password)
  end

  test "should handle validation errors with html format" do
    patch settings_path, params: {
      app_setting: { default_time_zone: "" },
    }

    assert_response(:unprocessable_entity)
    assert_equal("Please review the errors below.", flash.now[:alert])
  end

  test "should handle validation errors with turbo_stream format" do
    patch settings_path,
      params: {
        app_setting: { default_time_zone: "" },
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:unprocessable_entity)
  end

  test "should reset settings to defaults" do
    @app_setting.update!(
      default_time_zone: "America/New_York",
      default_calendar_identifier: "Work",
      app_host: "example.com",
      app_protocol: "https",
      app_port: "443",
    )

    post reset_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Settings reset to defaults.", flash[:notice])

    @app_setting.reload

    assert_equal("UTC", @app_setting.default_time_zone)
    assert_nil(@app_setting.default_calendar_identifier)
    assert_nil(@app_setting.app_host)
    assert_equal("http", @app_setting.app_protocol)
  end

  test "should reset apple credentials to nil" do
    @app_setting.update!(
      apple_username: "user@example.com",
      apple_app_password: "password123",
    )

    post reset_settings_path

    assert_redirected_to(edit_settings_path)
    @app_setting.reload

    assert_nil(@app_setting.app_port)
    assert_nil(@app_setting.apple_username)
    assert_nil(@app_setting.apple_app_password)
  end

  test "should reset settings with turbo_stream format" do
    @app_setting.update!(default_time_zone: "America/New_York")

    post reset_settings_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)

    @app_setting.reload

    assert_equal("UTC", @app_setting.default_time_zone)
  end

  test "should rotate credential key with html format" do
    AppSetting.any_instance.expects(:rotate_credentials_key!).once

    post rotate_credential_key_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Credential key rotated.", flash[:notice])
  end

  test "should rotate credential key with turbo_stream format" do
    AppSetting.any_instance.expects(:rotate_credentials_key!).once

    post rotate_credential_key_settings_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)
  end

  test "should handle key rotation error with html format" do
    error = CalendarHub::CredentialEncryption::KeyRotationError.new("Rotation failed")
    AppSetting.any_instance.expects(:rotate_credentials_key!).raises(error)

    post rotate_credential_key_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Rotating credential key failed: Rotation failed", flash[:alert])
  end

  test "should handle key rotation error with turbo_stream format" do
    error = CalendarHub::CredentialEncryption::KeyRotationError.new("Rotation failed")
    AppSetting.any_instance.expects(:rotate_credentials_key!).raises(error)

    post rotate_credential_key_settings_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)
  end

  test "should test calendar with identifier present" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_match(/Apple Calendar reachable. Destination found/, flash[:notice])
  end

  test "should test calendar with identifier present using turbo_stream" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)
  end

  test "should test calendar without identifier (fallback path)" do
    @app_setting.update!(default_calendar_identifier: nil)

    client_mock = mock("client")
    client_mock.expects(:send).with(:follow_well_known).returns("https://caldav.icloud.com/principals/user")
    client_mock.expects(:send).with(:fetch_calendar_home_set, "https://caldav.icloud.com/principals/user").returns("https://caldav.icloud.com/calendars/user/")
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Apple Calendar reachable. Credentials accepted.", flash[:notice])
  end

  test "should test calendar with empty string identifier (fallback path)" do
    @app_setting.update!(default_calendar_identifier: "")

    client_mock = mock("client")
    client_mock.expects(:send).with(:follow_well_known).returns("https://caldav.icloud.com/principals/user")
    client_mock.expects(:send).with(:fetch_calendar_home_set, "https://caldav.icloud.com/principals/user").returns("https://caldav.icloud.com/calendars/user/")
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Apple Calendar reachable. Credentials accepted.", flash[:notice])
  end

  test "should test calendar with custom credentials from params" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")

    AppleCalendar::Client.expects(:new).with(
      credentials: { username: "test@example.com", app_specific_password: "testpass123" },
    ).returns(client_mock)

    post test_calendar_settings_path, params: {
      apple_username: "test@example.com",
      apple_app_password: "testpass123",
    }

    assert_redirected_to(edit_settings_path)
    assert_match(/Apple Calendar reachable. Destination found/, flash[:notice])
  end

  test "should test calendar with only username param" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")

    AppleCalendar::Client.expects(:new).with(
      credentials: { username: "test@example.com", app_specific_password: nil },
    ).returns(client_mock)

    post test_calendar_settings_path, params: {
      apple_username: "test@example.com",
    }

    assert_redirected_to(edit_settings_path)
    assert_match(/Apple Calendar reachable. Destination found/, flash[:notice])
  end

  test "should test calendar with only password param" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")

    AppleCalendar::Client.expects(:new).with(
      credentials: { username: nil, app_specific_password: "testpass123" },
    ).returns(client_mock)

    post test_calendar_settings_path, params: {
      apple_app_password: "testpass123",
    }

    assert_redirected_to(edit_settings_path)
    assert_match(/Apple Calendar reachable. Destination found/, flash[:notice])
  end

  test "should test calendar with default credentials when no params" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").returns("https://caldav.icloud.com/calendars/user/Work")
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_match(/Apple Calendar reachable. Destination found/, flash[:notice])
  end

  test "should handle calendar test failure with html format" do
    @app_setting.update!(default_calendar_identifier: "Work")

    AppleCalendar::Client.expects(:new).raises(StandardError.new("Connection failed"))

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Apple Calendar test failed: Connection failed", flash[:alert])
  end

  test "should handle calendar test failure with turbo_stream format" do
    @app_setting.update!(default_calendar_identifier: "Work")

    AppleCalendar::Client.expects(:new).raises(StandardError.new("Connection failed"))

    post test_calendar_settings_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response(:success)
    assert_match(/turbo-stream/, response.content_type)
  end

  test "should handle calendar test failure during discovery" do
    @app_setting.update!(default_calendar_identifier: "Work")

    client_mock = mock("client")
    client_mock.expects(:send).with(:discover_calendar_url, "Work").raises(StandardError.new("Discovery failed"))
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Apple Calendar test failed: Discovery failed", flash[:alert])
  end

  test "should handle calendar test failure during fallback" do
    @app_setting.update!(default_calendar_identifier: nil)

    client_mock = mock("client")
    client_mock.expects(:send).with(:follow_well_known).raises(StandardError.new("Well-known failed"))
    AppleCalendar::Client.expects(:new).returns(client_mock)

    post test_calendar_settings_path

    assert_redirected_to(edit_settings_path)
    assert_equal("Apple Calendar test failed: Well-known failed", flash[:alert])
  end

  test "set_settings before_action sets @settings" do
    get settings_path

    assert_response(:success)
  end

  test "settings_params filters allowed parameters" do
    patch settings_path, params: {
      app_setting: {
        default_time_zone: "America/New_York",
        unauthorized_param: "should_be_filtered",
        id: "should_be_filtered",
      },
    }

    assert_redirected_to(edit_settings_path)

    @app_setting.reload

    assert_equal("America/New_York", @app_setting.default_time_zone)
  end

  test "should handle nil values in string fields" do
    patch settings_path, params: {
      app_setting: {
        app_host: nil,
        apple_username: nil,
      },
    }

    assert_redirected_to(edit_settings_path)
  end
end
