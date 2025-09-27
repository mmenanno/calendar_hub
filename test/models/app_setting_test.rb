# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  def setup
    super
    @original_path = ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"]
    @tmp_key_path = Rails.root.join("tmp", "test_credential_key_#{SecureRandom.hex(4)}")
    ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"] = @tmp_key_path.to_s
    CalendarHub::CredentialEncryption.reset!
    CalendarHub::CredentialEncryption.ensure_key!
  end

  def teardown
    CalendarHub::CredentialEncryption.reset!
    File.delete(@tmp_key_path) if @tmp_key_path && File.exist?(@tmp_key_path)
    if @original_path
      ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"] = @original_path
    else
      ENV.delete("CALENDAR_HUB_CREDENTIAL_KEY_PATH")
    end
    super
  end

  test "stores apple credentials encrypted" do
    settings = AppSetting.instance
    settings.apple_username = "user@example.com"
    settings.apple_app_password = "secret-pass"

    assert(settings.save)

    reloaded = AppSetting.instance

    assert_equal("user@example.com", reloaded.apple_username)
    assert_equal("secret-pass", reloaded.apple_app_password)
  end

  test "persists nil values when blank" do
    settings = AppSetting.instance
    settings.apple_username = ""
    settings.apple_app_password = nil

    assert(settings.save)

    reloaded = AppSetting.instance

    assert_nil(reloaded.apple_username)
    assert_nil(reloaded.apple_app_password)
  end

  test "rotate_credentials_key! reencrypts payload with new key" do
    settings = AppSetting.instance
    settings.apple_username = "rotate@example.com"
    settings.apple_app_password = "rotate-pass"

    assert(settings.save)

    original_fingerprint = settings.credential_key_fingerprint

    settings.rotate_credentials_key!
    settings.reload

    refute_equal(original_fingerprint, settings.credential_key_fingerprint)
    assert_equal("rotate@example.com", settings.apple_username)
    assert_equal("rotate-pass", settings.apple_app_password)
  end
end
