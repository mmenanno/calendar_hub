# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

module CalendarHub
  # KeyStore persists the application secrets (credential key and secret_key_base)
  # in a single JSON document to support rotation and metadata tracking.
  #
  # A missing file means "no keys yet"; an unreadable one raises
  # CorruptStoreError rather than being replaced, since new keys would make
  # every stored credential undecryptable. Writes are atomic and keep the
  # previous document as key_store.json.bak.
  class KeyStore
    STORE_ENV_KEY = "CALENDAR_HUB_KEY_STORE_PATH"
    DEFAULT_FILENAME = "key_store.json"
    BACKUP_SUFFIX = ".bak"
    CREDENTIAL_KEY_LENGTH = 64
    SECRET_KEY_BASE_LENGTH = 128

    class InvalidKeyError < StandardError; end
    class CorruptStoreError < StandardError; end
    class << self
      def instance
        new
      end

      def reset!; end
    end

    attr_reader :store_path

    def initialize(path: nil)
      resolved_path = path || resolve_store_path
      @store_path = Pathname.new(resolved_path).expand_path
      @mutex = Mutex.new
      @store = nil
    end

    def credential_key
      read_value("credential_key")
    end

    def credential_key_generated_at
      extract_timestamp("credential_key")
    end

    def secret_key_base
      read_value("secret_key_base")
    end

    def write_credential_key!(hex_key)
      validate_hex!(hex_key, CREDENTIAL_KEY_LENGTH)
      write_value("credential_key", hex_key, include_timestamp: true)
    end

    def write_secret_key_base!(hex_secret)
      validate_hex!(hex_secret, SECRET_KEY_BASE_LENGTH)
      write_value("secret_key_base", hex_secret, include_timestamp: true)
    end

    # The previous store document, written before every overwrite.
    def backup_path
      Pathname.new("#{store_path}#{BACKUP_SUFFIX}")
    end

    private

    def resolve_store_path
      ENV[STORE_ENV_KEY].presence || Rails.root.join("storage", DEFAULT_FILENAME).to_s
    end

    def store
      @store ||= read_store
    end

    def read_store
      return {} unless store_path.exist?

      parse_store(store_path.read)
    end

    def parse_store(raw)
      raise corrupt_store_error("is empty") if raw.to_s.strip.empty?

      parsed = JSON.parse(raw)
      raise corrupt_store_error("does not contain a JSON object") unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise corrupt_store_error("is not valid JSON")
    end

    def corrupt_store_error(problem)
      CorruptStoreError.new(
        "Key store #{store_path} #{problem}. Restore it from a backup (see README \"Backups & restore\"), " \
        "or delete it to generate new keys — previously stored credentials will then have to be re-entered.",
      )
    end

    def read_value(key_name)
      entry = store[key_name]
      case entry
      when Hash
        entry["value"]
      when String
        entry
      end
    end

    def extract_timestamp(key_name)
      entry = store[key_name]
      raw = entry.is_a?(Hash) ? entry["generated_at"] : nil
      return if raw.blank?

      Time.zone.parse(raw)
    rescue ArgumentError
      nil
    end

    def write_value(key_name, value, include_timestamp:)
      @mutex.synchronize do
        # Re-read so values written meanwhile (e.g. by another process) are kept.
        data = read_store
        payload = { "value" => value }
        payload["generated_at"] = current_timestamp if include_timestamp
        data[key_name] = payload
        persist_store(data)
        @store = data
      end
      value
    end

    def persist_store(data)
      FileUtils.mkdir_p(store_path.dirname)
      atomic_write(backup_path, store_path.binread) if store_path.exist?
      atomic_write(store_path, JSON.pretty_generate(data))
    end

    # Writes to an owner-only temp file in the same directory, then renames
    # it over the target, so readers never see a partial file.
    def atomic_write(path, content)
      temp_path = path.dirname.join(".#{path.basename}.#{SecureRandom.hex(6)}.tmp")
      File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temp_path, path)
      renamed = true
      fsync_directory(path.dirname)
    ensure
      FileUtils.rm_f(temp_path) if temp_path && !renamed
    end

    # Makes the rename itself durable. Not supported everywhere; the rename
    # is atomic either way.
    def fsync_directory(directory)
      return if Gem.win_platform?

      File.open(directory, File::RDONLY, &:fsync)
    rescue SystemCallError, IOError
      nil
    end

    def validate_hex!(candidate, expected_length)
      return if valid_hex?(candidate, expected_length)

      raise InvalidKeyError, "Expected #{expected_length}-character hexadecimal value"
    end

    def valid_hex?(candidate, expected_length)
      candidate.is_a?(String) &&
        candidate.length == expected_length &&
        candidate.match?(/\A[0-9a-fA-F]+\z/)
    end

    def current_timestamp
      Time.now.utc.iso8601
    end
  end
end
