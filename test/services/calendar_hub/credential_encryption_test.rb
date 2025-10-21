# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class CredentialEncryptionTest < ActiveSupport::TestCase
    def setup
      super
      @original_path = ENV["CALENDAR_HUB_KEY_STORE_PATH"]
      @tmp_key_path = Rails.root.join("tmp", "key_store_test_#{SecureRandom.hex(4)}.json")
      ENV["CALENDAR_HUB_KEY_STORE_PATH"] = @tmp_key_path.to_s
      CredentialEncryption.reset!
    end

    def teardown
      CredentialEncryption.reset!
      if @tmp_key_path && File.exist?(@tmp_key_path)
        File.delete(@tmp_key_path)
      end
      if @original_path
        ENV["CALENDAR_HUB_KEY_STORE_PATH"] = @original_path
      else
        ENV.delete("CALENDAR_HUB_KEY_STORE_PATH")
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

    test "encrypt returns nil for blank payload" do
      CredentialEncryption.ensure_key!

      assert_nil(CredentialEncryption.encrypt(nil))
      assert_nil(CredentialEncryption.encrypt({}))
      assert_nil(CredentialEncryption.encrypt({ key: "" }))
      assert_nil(CredentialEncryption.encrypt({ key: nil }))
    end

    test "coerce_payload handles various input types" do
      CredentialEncryption.ensure_key!

      # Test nil
      result = CredentialEncryption.send(:coerce_payload, nil)

      assert_empty(result)

      # Test string with valid JSON
      result = CredentialEncryption.send(:coerce_payload, '{"key": "value"}')

      assert_equal("value", result[:key])

      # Test string with invalid JSON
      result = CredentialEncryption.send(:coerce_payload, "invalid json")

      assert_empty(result)

      # Test hash
      result = CredentialEncryption.send(:coerce_payload, { key: "value" })

      assert_equal("value", result[:key])

      # Test object that responds to to_h
      obj = Struct.new(:to_h).new({ key: "value" })
      result = CredentialEncryption.send(:coerce_payload, obj)

      assert_equal("value", result[:key])

      # Test other object
      result = CredentialEncryption.send(:coerce_payload, 123)

      assert_empty(result)
    end

    test "coerce_payload handles string with valid JSON that returns non-hash" do
      CredentialEncryption.ensure_key!

      # Test string with valid JSON that parses to an array (not a hash)
      # This should hit line 215: parsed.is_a?(Hash) ? parsed : empty_hash
      # But first we need to bypass the parse_json method which calls with_indifferent_access
      # Let's mock parse_json to return an array
      CredentialEncryption.stubs(:parse_json).returns(["array", "not", "hash"])

      result = CredentialEncryption.send(:coerce_payload, '["array", "not", "hash"]')

      assert_empty(result)
    ensure
      CredentialEncryption.unstub(:parse_json)
    end

    test "coerce_payload handles JSON parsing error in rescue block" do
      CredentialEncryption.ensure_key!

      # The parse_json method already handles JSON::ParserError, so we need to trigger
      # a JSON::ParserError from somewhere else in coerce_payload to hit line 228
      # Let's mock with_indifferent_access to raise JSON::ParserError

      # Create a mock object that will trigger the Hash branch but then raise JSON::ParserError
      hash_obj = { key: "value" }
      hash_obj.stubs(:with_indifferent_access).raises(JSON::ParserError, "Simulated JSON error")

      result = CredentialEncryption.send(:coerce_payload, hash_obj)

      # Should return empty_hash due to JSON::ParserError (line 228)
      assert_empty(result)
    ensure
      hash_obj.unstub(:with_indifferent_access) if hash_obj.respond_to?(:unstub)
    end

    test "coerce_payload handles object with each_pair but not to_h using mocha" do
      CredentialEncryption.ensure_key!

      # Create a mock object using Mocha that has each_pair but not to_h
      obj = mock("each_pair_object")

      # Set up the respond_to? behavior
      obj.stubs(:respond_to?).with(:to_h).returns(false)
      obj.stubs(:respond_to?).with(:each_pair).returns(true)

      # Mock the each_pair method to return an enumerable
      # The actual implementation calls .to_h on the result of each_pair
      each_pair_enumerator = [["key", "value"], ["another", "data"]]
      obj.stubs(:each_pair).returns(each_pair_enumerator)

      # This should hit line 222: value.each_pair.to_h.with_indifferent_access
      result = CredentialEncryption.send(:coerce_payload, obj)

      assert_equal("value", result[:key])
      assert_equal("data", result[:another])
    end

    test "normalize_payload filters blank values" do
      CredentialEncryption.ensure_key!

      input = {
        username: "user",
        password: "pass",
        blank_key: "",
        nil_key: nil,
        whitespace: "   ",
        symbol_key: :value,
      }

      result = CredentialEncryption.send(:normalize_payload, input)

      assert_equal("user", result["username"])
      assert_equal("pass", result["password"])
      assert_equal(:value, result["symbol_key"])
      refute(result.key?("blank_key"))
      refute(result.key?("nil_key"))
      refute(result.key?("whitespace"))
    end

    test "legacy_decrypt handles invalid message" do
      CredentialEncryption.ensure_key!

      # Test with invalid ciphertext
      result = CredentialEncryption.send(:legacy_decrypt, "invalid")

      assert_nil(result)
    end

    test "legacy_decrypt returns nil when legacy encryptor fails to initialize" do
      CredentialEncryption.ensure_key!

      # Stub rails_key_generator to raise an error
      CredentialEncryption.stubs(:rails_key_generator).raises(StandardError, "boom")

      result = CredentialEncryption.send(:legacy_decrypt, "some-ciphertext")

      assert_nil(result)
    ensure
      CredentialEncryption.unstub(:rails_key_generator)
    end

    test "legacy_app_setting_credentials returns nil for blank credentials" do
      settings = {}
      result = CredentialEncryption.send(:legacy_app_setting_credentials, settings)

      assert_nil(result)

      settings = { apple_username: "", apple_app_password: "" }
      result = CredentialEncryption.send(:legacy_app_setting_credentials, settings)

      assert_nil(result)
    end

    test "legacy_app_setting_credentials extracts credentials when present" do
      settings = {
        apple_username: "user@example.com",
        apple_app_password: "pass123",
        other_field: "ignored",
      }

      result = CredentialEncryption.send(:legacy_app_setting_credentials, settings)

      assert_equal("user@example.com", result[:apple_username])
      assert_equal("pass123", result[:apple_app_password])
      refute(result.key?(:other_field))
    end

    test "valid_key? validates key format" do
      # Valid key
      valid_key = SecureRandom.hex(32)

      assert(CredentialEncryption.send(:valid_key?, valid_key))

      # Invalid cases
      refute(CredentialEncryption.send(:valid_key?, nil))
      refute(CredentialEncryption.send(:valid_key?, ""))
      refute(CredentialEncryption.send(:valid_key?, "too-short"))
      refute(CredentialEncryption.send(:valid_key?, "a" * 63)) # too short
      refute(CredentialEncryption.send(:valid_key?, "a" * 65)) # too long
      refute(CredentialEncryption.send(:valid_key?, "g" * 64)) # invalid hex
    end

    test "write_key raises for invalid key" do
      assert_raises(ArgumentError) do
        CredentialEncryption.send(:write_key, "invalid")
      end
    end

    test "read_key raises for invalid key in file" do
      # Write invalid key directly to file
      path = CredentialEncryption.send(:key_path)
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "invalid-key")

      assert_raises(ArgumentError) do
        CredentialEncryption.send(:read_key)
      end
    ensure
      File.delete(path) if File.exist?(path)
    end

    test "key_location returns path as string" do
      location = CredentialEncryption.key_location

      assert_kind_of(String, location)
      assert_includes(location, "key_store")
    end

    test "reencrypt_calendar_sources skips sources with blank credentials" do
      CredentialEncryption.ensure_key!
      old_encryptor = CredentialEncryption.send(:current_encryptor)
      new_encryptor = CredentialEncryption.send(:build_encryptor, SecureRandom.hex(32))

      source = CalendarSource.create!(
        name: "Test Source",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "Inbox",
      )
      source.update_column(:credentials, nil) # rubocop:disable Rails/SkipsModelValidations

      # Should not raise any errors
      assert_nothing_raised do
        CredentialEncryption.send(:reencrypt_calendar_sources, old_encryptor, new_encryptor)
      end
    ensure
      source&.destroy
    end

    test "reencrypt_app_settings handles settings without apple credentials" do
      CredentialEncryption.ensure_key!
      old_encryptor = CredentialEncryption.send(:current_encryptor)
      new_encryptor = CredentialEncryption.send(:build_encryptor, SecureRandom.hex(32))

      # Should not raise any errors when no apple credentials exist
      assert_nothing_raised do
        CredentialEncryption.send(:reencrypt_app_settings, old_encryptor, new_encryptor)
      end
    end

    test "decrypt_for_rotation handles blank ciphertext" do
      CredentialEncryption.ensure_key!
      encryptor = CredentialEncryption.send(:current_encryptor)

      result = CredentialEncryption.send(:decrypt_for_rotation, nil, encryptor)

      assert_empty(result)

      result = CredentialEncryption.send(:decrypt_for_rotation, "", encryptor)

      assert_empty(result)
    end

    test "decrypt_with handles nil encryptor" do
      result = CredentialEncryption.send(:decrypt_with, "some-ciphertext", nil)

      assert_nil(result)
    end

    test "encrypt_with returns nil for blank data" do
      CredentialEncryption.ensure_key!
      encryptor = CredentialEncryption.send(:current_encryptor)

      result = CredentialEncryption.send(:encrypt_with, {}, encryptor)

      assert_nil(result)
    end

    test "parse_json handles invalid JSON" do
      result = CredentialEncryption.send(:parse_json, "invalid json")

      assert_empty(result)
    end

    test "ensure_key! with existing cached key" do
      CredentialEncryption.ensure_key!
      original_key = CredentialEncryption.instance_variable_get(:@current_key)

      # Call again - should return cached key
      key = CredentialEncryption.ensure_key!

      assert_equal(original_key, key)
    end

    test "key_status when key file doesn't exist" do
      # Remove the key file
      path = CredentialEncryption.send(:key_path)
      File.delete(path) if File.exist?(path)
      CredentialEncryption.reset!

      status = CredentialEncryption.key_status

      assert_equal(16, status[:fingerprint].length)
      assert_equal(path.to_s, status[:path])
      assert_kind_of(Time, status[:created_at])
    end

    test "legacy_encryptor creates encryptor successfully" do
      CredentialEncryption.ensure_key!

      # Reset to ensure legacy_encryptor is created fresh
      CredentialEncryption.remove_instance_variable(:@legacy_encryptor) if CredentialEncryption.instance_variable_defined?(:@legacy_encryptor)

      # This should hit line 183 (secret generation) and line 184 (encryptor creation)
      encryptor = CredentialEncryption.send(:legacy_encryptor)

      refute_nil(encryptor)
      assert_kind_of(ActiveSupport::MessageEncryptor, encryptor)
    end

    test "decrypt falls back to legacy_decrypt successfully" do
      CredentialEncryption.ensure_key!

      # Create a payload encrypted with legacy encryptor
      legacy_encryptor = CredentialEncryption.send(:legacy_encryptor)
      legacy_ciphertext = legacy_encryptor.encrypt_and_sign({ username: "legacy_user", password: "legacy_pass" }.to_json)

      # Mock current encryptor to fail, forcing fallback to legacy
      CredentialEncryption.send(:current_encryptor).stubs(:decrypt_and_verify).raises(ActiveSupport::MessageEncryptor::InvalidMessage)

      result = CredentialEncryption.decrypt(legacy_ciphertext)

      assert_equal("legacy_user", result[:username])
      assert_equal("legacy_pass", result[:password])
    ensure
      CredentialEncryption.send(:current_encryptor).unstub(:decrypt_and_verify)
    end

    test "write_key handles Windows platform" do
      CredentialEncryption.ensure_key!

      # Mock Gem.win_platform? to return true
      Gem.stubs(:win_platform?).returns(true)

      key = SecureRandom.hex(32)
      path = CredentialEncryption.send(:key_path)

      # Should not call File.chmod on Windows (hits the unless branch)
      File.expects(:chmod).never

      CredentialEncryption.send(:write_key, key)

      assert_path_exists(path)
    ensure
      Gem.unstub(:win_platform?)
    end

    test "reencrypt_calendar_sources handles encrypted data that fails to decrypt" do
      CredentialEncryption.ensure_key!
      old_encryptor = CredentialEncryption.send(:current_encryptor)
      new_encryptor = CredentialEncryption.send(:build_encryptor, SecureRandom.hex(32))

      source = CalendarSource.create!(
        name: "Test Source",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "Inbox",
      )
      # Set invalid ciphertext that will fail to decrypt
      source.update_column(:credentials, "invalid-ciphertext") # rubocop:disable Rails/SkipsModelValidations

      # Should handle the decrypt failure gracefully and skip this source
      assert_nothing_raised do
        CredentialEncryption.send(:reencrypt_calendar_sources, old_encryptor, new_encryptor)
      end
    ensure
      source&.destroy
    end

    test "reencrypt_calendar_sources skips sources where encrypt_with returns nil" do
      CredentialEncryption.ensure_key!
      old_encryptor = CredentialEncryption.send(:current_encryptor)
      new_encryptor = CredentialEncryption.send(:build_encryptor, SecureRandom.hex(32))

      source = CalendarSource.create!(
        name: "Test Source",
        ingestion_url: "https://example.com/feed.ics",
        calendar_identifier: "Inbox",
        credentials: { username: "user", password: "pass" },
      )

      # Mock encrypt_with to return nil (simulating encryption failure)
      CredentialEncryption.stubs(:encrypt_with).returns(nil)

      # Should skip the source when encryption fails
      assert_nothing_raised do
        CredentialEncryption.send(:reencrypt_calendar_sources, old_encryptor, new_encryptor)
      end
    ensure
      CredentialEncryption.unstub(:encrypt_with)
      source&.destroy
    end

    test "reencrypt_app_settings skips when encrypt_with returns nil" do
      CredentialEncryption.ensure_key!
      old_encryptor = CredentialEncryption.send(:current_encryptor)
      new_encryptor = CredentialEncryption.send(:build_encryptor, SecureRandom.hex(32))

      settings = AppSetting.instance
      settings.apple_username = "test@example.com"
      settings.apple_app_password = "test-password"
      settings.save!

      # Mock encrypt_with to return nil (simulating encryption failure)
      CredentialEncryption.stubs(:encrypt_with).returns(nil)

      # Should skip when encryption fails
      assert_nothing_raised do
        CredentialEncryption.send(:reencrypt_app_settings, old_encryptor, new_encryptor)
      end
    ensure
      CredentialEncryption.unstub(:encrypt_with)
      settings&.destroy
    end
  end
end
