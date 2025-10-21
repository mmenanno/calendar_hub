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

    test "credential_key returns nil when not set" do
      assert_nil(@store.credential_key)
    end

    test "secret_key_base returns nil when not set" do
      assert_nil(@store.secret_key_base)
    end
  end
end
