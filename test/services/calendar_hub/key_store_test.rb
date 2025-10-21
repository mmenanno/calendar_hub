# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class KeyStoreTest < ActiveSupport::TestCase
    def setup
      super
      @original_path = ENV["CALENDAR_HUB_KEY_STORE_PATH"]
      @store_path = Rails.root.join("tmp", "key_store_test_#{SecureRandom.hex(4)}.json")
      ENV["CALENDAR_HUB_KEY_STORE_PATH"] = @store_path.to_s
      CalendarHub::KeyStore.reset!
      @store = CalendarHub::KeyStore.instance
    end

    def teardown
      CalendarHub::KeyStore.reset!
      if @store_path && File.exist?(@store_path)
        File.delete(@store_path)
      end
      if @original_path
        ENV["CALENDAR_HUB_KEY_STORE_PATH"] = @original_path
      else
        ENV.delete("CALENDAR_HUB_KEY_STORE_PATH")
      end
      super
    end

    test "write_credential_key persists value and metadata" do
      key = SecureRandom.hex(32)

      @store.write_credential_key!(key)

      assert_equal(key, @store.credential_key)
      assert_kind_of(Time, @store.credential_key_generated_at)
    end

    test "write_secret_key_base persists and reads value" do
      secret = SecureRandom.hex(64)

      @store.write_secret_key_base!(secret)

      assert_equal(secret, @store.secret_key_base)
    end

    test "credential_key imports from legacy file when store empty" do
      legacy_key = SecureRandom.hex(32)
      legacy_path = Rails.root.join("tmp", "legacy_credential_key_#{SecureRandom.hex(4)}")
      File.write(legacy_path, legacy_key)

      begin
        @store.reset_cache!
        File.delete(@store_path) if File.exist?(@store_path)
        @store.stubs(:legacy_credential_key_path).returns(legacy_path)

        assert_equal(legacy_key, @store.credential_key)
        assert_path_exists(@store_path, "expected key store to be persisted")
      ensure
        @store.unstub(:legacy_credential_key_path)
        File.delete(legacy_path) if File.exist?(legacy_path)
      end
    end

    test "secret_key_base imports from legacy file when store empty" do
      legacy_secret = SecureRandom.hex(64)
      legacy_path = Rails.root.join("tmp", "legacy_secret_key_base_#{SecureRandom.hex(4)}")
      File.write(legacy_path, legacy_secret)

      begin
        @store.reset_cache!
        File.delete(@store_path) if File.exist?(@store_path)
        @store.stubs(:legacy_secret_key_base_path).returns(legacy_path)

        assert_equal(legacy_secret, @store.secret_key_base)
        assert_path_exists(@store_path, "expected key store to be persisted")
      ensure
        @store.unstub(:legacy_secret_key_base_path)
        File.delete(legacy_path) if File.exist?(legacy_path)
      end
    end
  end
end
