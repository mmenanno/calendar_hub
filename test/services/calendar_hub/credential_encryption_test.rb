# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class CredentialEncryptionTest < ActiveSupport::TestCase
    def setup
      super
      @original_path = ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"]
      @tmp_key_path = Rails.root.join("tmp", "credential_key_test_#{SecureRandom.hex(4)}")
      ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"] = @tmp_key_path.to_s
      CredentialEncryption.reset!
    end

    def teardown
      CredentialEncryption.reset!
      if @tmp_key_path && File.exist?(@tmp_key_path)
        File.delete(@tmp_key_path)
      end
      if @original_path
        ENV["CALENDAR_HUB_CREDENTIAL_KEY_PATH"] = @original_path
      else
        ENV.delete("CALENDAR_HUB_CREDENTIAL_KEY_PATH")
      end
      super
    end

    test "ensures key is generated on demand" do
      refute_path_exists(@tmp_key_path)

      CredentialEncryption.ensure_key!
      fingerprint = CredentialEncryption.key_fingerprint

      assert_path_exists(@tmp_key_path)
      assert_equal(16, fingerprint.length)
    end

    test "encrypt and decrypt round trip" do
      CredentialEncryption.ensure_key!

      payload = { username: "alice", password: "secret" }
      ciphertext = CredentialEncryption.encrypt(payload)

      refute_nil(ciphertext)

      decrypted = CredentialEncryption.decrypt(ciphertext)

      assert_equal("alice", decrypted[:username])
      assert_equal("secret", decrypted[:password])
    end

    test "decrypt returns empty hash for blank payload" do
      CredentialEncryption.ensure_key!

      assert_empty(CredentialEncryption.decrypt(nil))
      assert_empty(CredentialEncryption.decrypt(""))
    end

    test "key_status returns fingerprint and metadata" do
      CredentialEncryption.ensure_key!
      status = CredentialEncryption.key_status

      assert_equal(16, status[:fingerprint].length)
      assert_equal(@tmp_key_path.to_s, status[:path])
      assert_kind_of(Time, status[:created_at])
    end

    test "rotate! generates new key and reencrypts data" do
      CredentialEncryption.ensure_key!
      original_fingerprint = CredentialEncryption.key_fingerprint

      source = CalendarSource.create!(
        name: "Test Source",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "Inbox",
        credentials: { username: "user", password: "pass" },
      )
      settings = AppSetting.instance
      settings.apple_username = "initial@example.com"
      settings.apple_app_password = "initial-pass"
      settings.save!

      CredentialEncryption.rotate!
      new_fingerprint = CredentialEncryption.key_fingerprint

      refute_equal(original_fingerprint, new_fingerprint)

      fresh_source = CalendarSource.find(source.id)
      creds = fresh_source.credentials.with_indifferent_access

      assert_equal("user", creds[:username])
      assert_equal("pass", creds[:password])

      fresh_settings = AppSetting.instance.reload

      assert_equal("initial@example.com", fresh_settings.apple_username)
      assert_equal("initial-pass", fresh_settings.apple_app_password)

      ciphertext = fresh_source.read_attribute(:credentials)
      decrypted = CredentialEncryption.decrypt(ciphertext)

      assert_equal("user", decrypted[:username])
      assert_equal("pass", decrypted[:password])
    ensure
      source.destroy
    end

    test "rotate! raises KeyRotationError when persistence fails" do
      CredentialEncryption.ensure_key!
      original_fingerprint = CredentialEncryption.key_fingerprint

      source = CalendarSource.create!(
        name: "Test Source",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "Inbox",
        credentials: { username: "user", password: "pass" },
      )

      CalendarSource
        .any_instance
        .stubs(:update_column)
        .raises(StandardError, "boom")

      assert_raises(CredentialEncryption::KeyRotationError) do
        CredentialEncryption.rotate!
      end

      final_fingerprint = CredentialEncryption.key_fingerprint

      assert_equal(original_fingerprint, final_fingerprint)
    ensure
      CalendarSource.any_instance.unstub(:update_column)
      source.destroy
    end
  end
end
