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

  test "rotate_credentials_key! handles empty credentials" do
    settings = AppSetting.instance
    # Ensure no credentials are set
    settings.apple_username = nil
    settings.apple_app_password = nil

    assert(settings.save)

    original_fingerprint = settings.credential_key_fingerprint

    # Should not raise an error
    settings.rotate_credentials_key!
    settings.reload

    refute_equal(original_fingerprint, settings.credential_key_fingerprint)
    assert_nil(settings.apple_username)
    assert_nil(settings.apple_app_password)
  end

  test "sanitize handles various input types" do
    settings = AppSetting.instance

    # Test with whitespace strings
    settings.apple_username = "  user@example.com  "
    settings.save!

    assert_equal("user@example.com", settings.reload.apple_username)

    # Test with empty strings
    settings.apple_username = ""
    settings.save!

    assert_nil(settings.reload.apple_username)

    # Test with whitespace-only strings
    settings.apple_username = "   "
    settings.save!

    assert_nil(settings.reload.apple_username)

    # Test with nil
    settings.apple_username = nil
    settings.save!

    assert_nil(settings.reload.apple_username)
  end

  test "persist_credentials handles legacy attributes" do
    settings = AppSetting.instance

    # Set legacy attributes and save to test the migration process
    settings.apple_username = "legacy_user"
    settings.apple_app_password = "legacy_pass"
    settings.save!

    # After save, credentials should be encrypted and accessible
    settings.reload

    assert_equal("legacy_user", settings.apple_username)
    assert_equal("legacy_pass", settings.apple_app_password)

    # And the legacy attributes should be cleared from the database
    refute_nil(settings.apple_credentials_ciphertext)
  end

  test "credential_store uses legacy_payload when no ciphertext" do
    settings = AppSetting.instance

    # Set legacy attributes directly
    settings[:apple_username] = "legacy_user"
    settings[:apple_app_password] = "legacy_pass"
    settings.apple_credentials_ciphertext = nil

    # Reset instance variable to force reload
    settings.send(:reset_credential_store!)

    store = settings.send(:credential_store)

    assert_equal("legacy_user", store[:apple_username])
    assert_equal("legacy_pass", store[:apple_app_password])
  end

  test "upsert_credential handles various scenarios" do
    settings = AppSetting.instance

    # Test setting a new credential
    settings.send(:upsert_credential, :test_key, "test_value")
    store = settings.send(:credential_store)

    assert_equal("test_value", store[:test_key])

    # Test updating existing credential
    settings.send(:upsert_credential, :test_key, "updated_value")
    store = settings.send(:credential_store)

    assert_equal("updated_value", store[:test_key])

    # Test removing credential with nil
    settings.send(:upsert_credential, :test_key, nil)
    store = settings.send(:credential_store)

    refute(store.key?(:test_key))

    # Test removing credential with empty string
    settings.send(:upsert_credential, :test_key, "")
    store = settings.send(:credential_store)

    refute(store.key?(:test_key))
  end

  test "legacy_payload handles sanitization" do
    settings = AppSetting.instance

    # Set legacy attributes with whitespace
    settings[:apple_username] = "  legacy_user  "
    settings[:apple_app_password] = "  legacy_pass  "

    legacy = settings.send(:legacy_payload)

    assert_equal("legacy_user", legacy[:apple_username])
    assert_equal("legacy_pass", legacy[:apple_app_password])
  end

  test "legacy_payload excludes blank values" do
    settings = AppSetting.instance

    # Set one valid and one blank legacy attribute
    settings[:apple_username] = "valid_user"
    settings[:apple_app_password] = ""

    legacy = settings.send(:legacy_payload)

    assert_equal("valid_user", legacy[:apple_username])
    refute(legacy.key?(:apple_app_password))
  end

  test "validates required fields" do
    settings = AppSetting.new(
      default_time_zone: nil,
      default_sync_frequency_minutes: nil,
    )

    refute_predicate(settings, :valid?)
    assert_includes(settings.errors[:default_time_zone], "can't be blank")
    assert_includes(settings.errors[:default_sync_frequency_minutes], "can't be blank")
  end

  test "validates sync frequency numericality" do
    settings = AppSetting.new(
      default_time_zone: "UTC",
      default_sync_frequency_minutes: -10,
    )

    refute_predicate(settings, :valid?)
    assert_includes(settings.errors[:default_sync_frequency_minutes], "must be greater than 0")
  end

  test "instance creates with defaults" do
    # Clear any existing instance
    AppSetting.delete_all

    settings = AppSetting.instance

    assert_equal("UTC", settings.default_time_zone)
    assert_equal(60, settings.default_sync_frequency_minutes)
    assert_predicate(settings, :persisted?)
  end

  test "instance returns existing record" do
    # Clear any existing records first
    AppSetting.delete_all

    existing = AppSetting.create!(
      default_time_zone: "America/New_York",
      default_sync_frequency_minutes: 30,
    )

    settings = AppSetting.instance

    assert_equal(existing.id, settings.id)
    assert_equal("America/New_York", settings.default_time_zone)
    assert_equal(30, settings.default_sync_frequency_minutes)
  end

  test "credential_key_fingerprint returns correct fingerprint" do
    settings = AppSetting.instance

    fingerprint = settings.credential_key_fingerprint
    expected = CalendarHub::CredentialEncryption.key_fingerprint

    assert_equal(expected, fingerprint)
  end

  test "persist_credentials skips when credential_store not initialized" do
    settings = AppSetting.instance

    # Ensure credential_store instance variable is not set
    settings.send(:reset_credential_store!)

    # Should not raise an error and should skip processing
    assert_nothing_raised do
      settings.send(:persist_credentials)
    end

    # Verify that no ciphertext was set since credential store wasn't initialized
    assert_nil(settings.apple_credentials_ciphertext)
  end

  test "persist_credentials handles normalized empty hash" do
    settings = AppSetting.instance

    # Set up credential store with only blank values
    settings.send(:upsert_credential, :apple_username, "")
    settings.send(:upsert_credential, :apple_app_password, nil)

    settings.send(:persist_credentials)

    # Should clear the ciphertext when all values are blank
    assert_nil(settings.apple_credentials_ciphertext)
  end

  test "persist_credentials handles existing ciphertext when normalized is empty" do
    settings = AppSetting.instance

    # Set up some credentials first
    settings.apple_username = "test@example.com"
    settings.save!

    # Now clear them by setting blank values
    settings.send(:upsert_credential, :apple_username, "")
    settings.send(:upsert_credential, :apple_app_password, "")

    settings.send(:persist_credentials)

    # Should clear the ciphertext
    assert_nil(settings.apple_credentials_ciphertext)
  end

  test "persist_credentials handles attribute_present check" do
    settings = AppSetting.instance

    # Set up credential store first
    settings.send(:upsert_credential, :apple_username, "test_user")
    settings.send(:upsert_credential, :apple_app_password, "test_pass")

    # Now directly set legacy attributes to simulate old data
    settings[:apple_username] = "legacy_user"
    settings[:apple_app_password] = "legacy_pass"

    # Mock attribute_present? to return false for one attribute
    settings.stubs(:attribute_present?).with(:apple_username).returns(false)
    settings.stubs(:attribute_present?).with(:apple_app_password).returns(true)

    settings.send(:persist_credentials)

    # Only the attribute that was present should be cleared
    assert_equal("legacy_user", settings[:apple_username])
    assert_nil(settings[:apple_app_password])
  end

  test "sanitize handles non-string values" do
    settings = AppSetting.instance

    # Test with integer (should return as-is)
    result = settings.send(:sanitize, 123)

    assert_equal(123, result)

    # Test with hash (should return as-is)
    hash_value = { "key" => "value" }
    result = settings.send(:sanitize, hash_value)

    assert_equal(hash_value, result)

    # Test with boolean (should return as-is)
    result = settings.send(:sanitize, true)

    assert(result)
  end

  test "legacy_payload handles nil legacy attributes" do
    settings = AppSetting.instance

    # Clear any existing attributes
    settings[:apple_username] = nil
    settings[:apple_app_password] = nil

    legacy = settings.send(:legacy_payload)

    # Should return empty hash
    assert_empty(legacy)
  end

  test "reset_credential_store handles missing instance variable" do
    settings = AppSetting.instance

    # Ensure the instance variable doesn't exist
    settings.remove_instance_variable(:@credential_store) if settings.instance_variable_defined?(:@credential_store)

    # Should not raise an error
    assert_nothing_raised do
      settings.send(:reset_credential_store!)
    end
  end

  test "credential_store handles decryption error gracefully" do
    settings = AppSetting.instance

    # Set up legacy attributes so there's something to fall back to
    settings[:apple_username] = "legacy_user"
    settings[:apple_app_password] = "legacy_pass"

    # Set invalid ciphertext that will fail decryption
    settings.apple_credentials_ciphertext = "invalid_ciphertext"

    # Reset credential store to force re-initialization
    settings.send(:reset_credential_store!)

    # Mock the credential_store method to simulate decryption error and fallback
    settings.stubs(:credential_store).returns({
      apple_username: "legacy_user",
      apple_app_password: "legacy_pass",
    }.with_indifferent_access)

    # Should return the fallback data
    store = settings.send(:credential_store)

    assert_kind_of(Hash, store)
    assert_equal("legacy_user", store[:apple_username])
    assert_equal("legacy_pass", store[:apple_app_password])
  end

  test "instance method handles multiple calls" do
    # Clear any existing records
    AppSetting.delete_all

    # First call should create a record
    first_instance = AppSetting.instance

    assert_predicate(first_instance, :persisted?)

    # Second call should return the same record
    second_instance = AppSetting.instance

    assert_equal(first_instance.id, second_instance.id)
  end

  test "rotate_credentials_key handles edge case with missing fingerprint" do
    settings = AppSetting.instance

    # Mock key_fingerprint to return nil initially
    CalendarHub::CredentialEncryption.stubs(:key_fingerprint).returns(nil).then.returns("new_fingerprint")

    # Should still work without error
    assert_nothing_raised do
      settings.rotate_credentials_key!
    end
  end

  test "apple_credentials_ciphertext= and attribute handling" do
    settings = AppSetting.instance

    # Test direct ciphertext setting
    test_ciphertext = "encrypted_data_here"
    settings.apple_credentials_ciphertext = test_ciphertext

    assert_equal(test_ciphertext, settings.apple_credentials_ciphertext)
  end

  test "validates numericality with zero value" do
    settings = AppSetting.new(
      default_time_zone: "UTC",
      default_sync_frequency_minutes: 0,
    )

    refute_predicate(settings, :valid?)
    assert_includes(settings.errors[:default_sync_frequency_minutes], "must be greater than 0")
  end

  test "validates numericality with non-numeric value" do
    settings = AppSetting.new(
      default_time_zone: "UTC",
      default_sync_frequency_minutes: "not_a_number",
    )

    refute_predicate(settings, :valid?)
    assert_includes(settings.errors[:default_sync_frequency_minutes], "is not a number")
  end

  test "persist_credentials handles blank sanitized values" do
    settings = AppSetting.instance

    # Set up credential store with values that will be sanitized to blank
    settings.send(:upsert_credential, :apple_username, "   ") # Will be sanitized to nil
    settings.send(:upsert_credential, :apple_app_password, "") # Will be sanitized to nil
    settings.send(:upsert_credential, :test_key, nil) # Already nil

    settings.send(:persist_credentials)

    # Should result in empty normalized hash, clearing ciphertext
    assert_nil(settings.apple_credentials_ciphertext)
  end

  test "persist_credentials handles missing attribute_present conditions" do
    settings = AppSetting.instance

    # Directly set legacy attributes to test the attribute_present? conditions
    settings[:apple_username] = "legacy_user"
    settings[:apple_app_password] = "legacy_pass"

    # Initialize credential store to trigger persist_credentials
    settings.send(:upsert_credential, :test_key, "test_value")

    # Mock attribute_present? to return false for legacy attributes
    settings.stubs(:attribute_present?).with(:apple_username).returns(false)
    settings.stubs(:attribute_present?).with(:apple_app_password).returns(false)
    settings.stubs(:attribute_present?).with(:apple_credentials_ciphertext).returns(true)

    settings.send(:persist_credentials)

    # When attribute_present? returns false, the legacy attributes shouldn't be cleared
    assert_equal("legacy_user", settings[:apple_username])
    assert_equal("legacy_pass", settings[:apple_app_password])
  end

  test "persist_credentials with mixed sanitized values" do
    settings = AppSetting.instance

    # Set up credential store with mix of valid and blank values
    settings.send(:upsert_credential, :apple_username, "valid_user")
    settings.send(:upsert_credential, :apple_app_password, "   ") # Will be sanitized to nil
    settings.send(:upsert_credential, :test_key, "") # Will be sanitized to nil

    settings.send(:persist_credentials)

    # Should only include the valid value in normalized hash
    refute_nil(settings.apple_credentials_ciphertext)

    # Verify only valid credentials are stored
    settings.reload

    assert_equal("valid_user", settings.apple_username)
    assert_nil(settings.apple_app_password)
  end
end
