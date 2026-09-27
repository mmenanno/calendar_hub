# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class KeyStoreTest < ActiveSupport::TestCase
    def setup
      super
      @original_path = ENV.fetch("CALENDAR_HUB_KEY_STORE_PATH", nil)
      @store_path = Rails.root.join("tmp", "key_store_test_#{SecureRandom.hex(4)}.json")
      ENV["CALENDAR_HUB_KEY_STORE_PATH"] = @store_path.to_s
      CalendarHub::KeyStore.reset!
      @store = CalendarHub::KeyStore.instance
    end

    def teardown
      CalendarHub::KeyStore.reset!
      FileUtils.rm_f([@store_path, "#{@store_path}.bak"]) if @store_path
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

    test "raises CorruptStoreError for an empty store file" do
      File.write(@store_path, "  \n")

      error = assert_raises(KeyStore::CorruptStoreError) { @store.credential_key }

      assert_includes(error.message, @store_path.to_s)
      assert_includes(error.message, "is empty")
    end

    test "raises CorruptStoreError for invalid JSON" do
      File.write(@store_path, '{"credential_key": ')

      error = assert_raises(KeyStore::CorruptStoreError) { @store.secret_key_base }

      assert_includes(error.message, "Restore it from a backup")
      assert_includes(error.message, "delete it to generate new keys")
    end

    test "raises CorruptStoreError when the JSON is not an object" do
      File.write(@store_path, "[1, 2]")

      assert_raises(KeyStore::CorruptStoreError) { @store.credential_key }
    end

    test "never overwrites a corrupt store" do
      File.write(@store_path, "garbage")

      assert_raises(KeyStore::CorruptStoreError) { @store.write_credential_key!(SecureRandom.hex(32)) }
      assert_equal("garbage", File.read(@store_path))
    end

    test "writes the store atomically with owner-only permissions and no leftovers" do
      @store.write_credential_key!(SecureRandom.hex(32))
      @store.write_secret_key_base!(SecureRandom.hex(64))

      assert_equal(0o600, File.stat(@store_path).mode & 0o777)
      assert_empty(temp_files)
    end

    test "removes the temp file when the write fails" do
      File.stubs(:rename).raises(Errno::EACCES)

      assert_raises(Errno::EACCES) { @store.write_credential_key!(SecureRandom.hex(32)) }
      assert_empty(temp_files)
      refute_path_exists(@store_path)
    ensure
      File.unstub(:rename)
    end

    test "keeps the previous store as key_store.json.bak when overwriting" do
      old_key = SecureRandom.hex(32)
      new_key = SecureRandom.hex(32)
      @store.write_credential_key!(old_key)

      KeyStore.instance.write_credential_key!(new_key)

      backup = Pathname.new("#{@store_path}.bak")

      assert_equal(old_key, JSON.parse(backup.read).dig("credential_key", "value"))
      assert_equal(0o600, backup.stat.mode & 0o777)
      assert_equal(new_key, KeyStore.instance.credential_key)
      assert_empty(temp_files)
    end

    test "does not create a backup when there was no store yet" do
      @store.write_credential_key!(SecureRandom.hex(32))

      refute_path_exists("#{@store_path}.bak")
    end

    test "writes merge with values written by other instances" do
      secret = SecureRandom.hex(64)
      @store.credential_key # memoizes the (empty) store
      KeyStore.instance.write_secret_key_base!(secret)

      @store.write_credential_key!(SecureRandom.hex(32))

      assert_equal(secret, KeyStore.instance.secret_key_base)
    end

    private

    def temp_files
      Dir.glob(File.join(File.dirname(@store_path), ".#{File.basename(@store_path)}*.tmp"))
    end
  end
end
