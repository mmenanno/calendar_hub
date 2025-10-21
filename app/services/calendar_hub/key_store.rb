# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "time"

module CalendarHub
  # KeyStore persists the application secrets (credential key and secret_key_base)
  # in a single JSON document to support rotation and metadata tracking.
  class KeyStore
    STORE_ENV_KEY = "CALENDAR_HUB_KEY_STORE_PATH"
    DEFAULT_FILENAME = "key_store.json"
    CREDENTIAL_KEY_LENGTH = 64
    SECRET_KEY_BASE_LENGTH = 128

    class InvalidKeyError < StandardError; end
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
      @data = nil
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

    def reset_cache!
      @mutex.synchronize do
        @data = nil
      end
    end

    private

    def resolve_store_path
      ENV[STORE_ENV_KEY].presence || Rails.root.join("storage", DEFAULT_FILENAME).to_s
    end

    def load_store
      @data ||= read_store
    end

    def read_store
      return {} unless store_path.exist?

      raw = store_path.read
      parse_store(raw)
    end

    def parse_store(raw)
      trimmed = raw.to_s.strip
      return {} if trimmed.empty?

      parsed = JSON.parse(trimmed)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def read_value(key_name)
      entry = load_store[key_name]
      case entry
      when Hash
        entry["value"]
      when String
        entry
      end
    end

    def extract_timestamp(key_name)
      entry = load_store[key_name]
      raw = entry.is_a?(Hash) ? entry["generated_at"] : nil
      return if raw.blank?

      Time.zone.parse(raw)
    rescue ArgumentError
      nil
    end

    def write_value(key_name, value, include_timestamp:)
      @mutex.synchronize do
        data = load_store
        payload = { "value" => value }
        payload["generated_at"] = current_timestamp if include_timestamp
        data[key_name] = payload
        persist_store
      end
      value
    end

    def persist_store
      FileUtils.mkdir_p(store_path.dirname)
      store_path.write(JSON.pretty_generate(load_store))
      store_path.chmod(0o600) unless Gem.win_platform?
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
