# frozen_string_literal: true

require "digest"
require "fileutils"

module CalendarHub
  module CredentialEncryption
    extend self

    SALT = "calendar-source-salt"
    KEY_BYTES = 32
    HEX_LENGTH = KEY_BYTES * 2

    class KeyRotationError < StandardError; end

    def encrypt(payload)
      hash = coerce_payload(payload)
      normalized = normalize_payload(hash)
      return if normalized.blank?

      current_encryptor.encrypt_and_sign(normalized.to_json)
    end

    def decrypt(ciphertext)
      return empty_hash if ciphertext.blank?

      decrypted = current_encryptor.decrypt_and_verify(ciphertext)
      coerce_payload(decrypted)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      legacy_decrypt(ciphertext) || empty_hash
    end

    def rotate!
      mutex.synchronize do
        ensure_key!
        old_encryptor = @current_encryptor
        new_key = generate_key
        new_encryptor = build_encryptor(new_key)

        ActiveRecord::Base.transaction do
          reencrypt_calendar_sources(old_encryptor, new_encryptor)
          reencrypt_app_settings(old_encryptor, new_encryptor)
        end

        write_key(new_key)
        @current_key = new_key
        @current_encryptor = new_encryptor
      end
    rescue => e
      reset_cached_encryptor!
      remove_instance_variable(:@legacy_encryptor) if instance_variable_defined?(:@legacy_encryptor)
      raise KeyRotationError, e.message
    end

    def ensure_key!
      if instance_variable_defined?(:@current_key) && @current_key.present?
        return @current_key
      end

      mutex.synchronize do
        unless instance_variable_defined?(:@current_key) && @current_key.present?
          next_key = if key_path.exist?
            read_key
          else
            generate_and_store_key
          end
          @current_key = next_key
          @current_encryptor = build_encryptor(@current_key)
        end
      end

      @current_key
    end

    def key_fingerprint
      ensure_key!
      Digest::SHA256.hexdigest(@current_key)[0, 16]
    end

    def key_location
      key_path.to_s
    end

    def key_status
      ensure_key!
      path = key_path
      {
        fingerprint: key_fingerprint,
        path: path.to_s,
        created_at: path.exist? ? path.stat.mtime : nil,
      }
    end

    def reset!
      mutex.synchronize do
        reset_cached_encryptor!
        remove_instance_variable(:@key_path) if instance_variable_defined?(:@key_path)
        remove_instance_variable(:@legacy_encryptor) if instance_variable_defined?(:@legacy_encryptor)
      end
    end

    private

    def reset_cached_encryptor!
      remove_instance_variable(:@current_key) if instance_variable_defined?(:@current_key)
      remove_instance_variable(:@current_encryptor) if instance_variable_defined?(:@current_encryptor)
    end

    def reencrypt_calendar_sources(old_encryptor, new_encryptor)
      CalendarSource.where.not(credentials: nil).find_each do |source|
        ciphertext = source.read_attribute(:credentials)
        next if ciphertext.blank?

        data = decrypt_for_rotation(ciphertext, old_encryptor)
        encrypted = encrypt_with(data, new_encryptor)
        next if encrypted.blank?

        # Updating the raw encrypted payload; skip the custom credentials= writer.
        source.update_column(:credentials, encrypted) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def reencrypt_app_settings(old_encryptor, new_encryptor)
      AppSetting.find_each do |settings|
        ciphertext = settings.read_attribute(:apple_credentials_ciphertext) || settings.read_attribute(:apple_username)

        data = if ciphertext.present?
          decrypt_for_rotation(ciphertext, old_encryptor)
        else
          legacy_app_setting_credentials(settings)
        end

        next if data.blank?

        encrypted = encrypt_with(data, new_encryptor)
        next if encrypted.blank?

        updates = { apple_credentials_ciphertext: encrypted }
        updates[:apple_username] = nil if settings.has_attribute?(:apple_username)
        updates[:apple_app_password] = nil if settings.has_attribute?(:apple_app_password)
        settings.update_columns(updates) # rubocop:disable Rails/SkipsModelValidations -- migrating encrypted payload without triggering callbacks
      end
    end

    def encrypt_with(data, encryptor)
      hash = coerce_payload(data)
      normalized = normalize_payload(hash)
      return if normalized.blank?

      encryptor.encrypt_and_sign(normalized.to_json)
    end

    def decrypt_for_rotation(ciphertext, primary_encryptor)
      return empty_hash if ciphertext.blank?

      coerce_payload(
        decrypt_with(ciphertext, primary_encryptor) || legacy_decrypt(ciphertext),
      )
    end

    def decrypt_with(ciphertext, encryptor)
      return if ciphertext.blank? || encryptor.nil?

      decrypted = encryptor.decrypt_and_verify(ciphertext)
      coerce_payload(decrypted)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def legacy_decrypt(ciphertext)
      encryptor = legacy_encryptor
      return unless encryptor

      decrypted = encryptor.decrypt_and_verify(ciphertext)
      hash = coerce_payload(decrypted)
      hash.presence
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def legacy_encryptor
      @legacy_encryptor ||= begin
        secret = rails_key_generator.generate_key("calendar_source_credentials", ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm")
      rescue
        nil
      end
    end

    def legacy_app_setting_credentials(settings)
      return if settings[:apple_username].blank? && settings[:apple_app_password].blank?

      creds = {}
      creds[:apple_username] = settings[:apple_username] if settings[:apple_username].present?
      creds[:apple_app_password] = settings[:apple_app_password] if settings[:apple_app_password].present?
      creds.with_indifferent_access
    end

    def rails_key_generator
      Rails.application.key_generator
    end

    def parse_json(json)
      JSON.parse(json).with_indifferent_access
    rescue JSON::ParserError
      empty_hash
    end

    def coerce_payload(value)
      case value
      when nil
        empty_hash
      when String
        parsed = parse_json(value)
        parsed.is_a?(Hash) ? parsed : empty_hash
      when Hash
        value.with_indifferent_access
      else
        if value.respond_to?(:to_h)
          value.to_h.with_indifferent_access
        elsif value.respond_to?(:each_pair)
          value.each_pair.to_h.with_indifferent_access
        else
          empty_hash
        end
      end
    rescue JSON::ParserError
      empty_hash
    end

    def normalize_payload(hash)
      hash.each_with_object({}) do |(key, val), memo|
        next if val.blank?

        memo[key.to_s] = val
      end
    end

    def empty_hash
      {}.with_indifferent_access
    end

    def current_encryptor
      ensure_key!
      @current_encryptor ||= build_encryptor(@current_key)
    end

    def build_encryptor(key)
      secret = ActiveSupport::KeyGenerator.new(key).generate_key(SALT, ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm")
    end

    def generate_and_store_key
      key = generate_key
      write_key(key)
      key
    end

    def write_key(key)
      raise ArgumentError, "Invalid key length" unless valid_key?(key)

      path = key_path
      FileUtils.mkdir_p(path.dirname)
      File.write(path, key)
      File.chmod(0o600, path) unless Gem.win_platform?
    end

    def read_key
      key = key_path.read.strip
      raise ArgumentError, "Invalid key length" unless valid_key?(key)

      key
    end

    def key_path
      @key_path ||= begin
        configured = ENV.fetch("CALENDAR_HUB_CREDENTIAL_KEY_PATH", Rails.root.join("storage/credential_key").to_s)
        Pathname.new(configured).expand_path
      end
    end

    def generate_key
      SecureRandom.hex(KEY_BYTES)
    end

    def valid_key?(candidate)
      candidate.is_a?(String) && candidate.present? && candidate.length == HEX_LENGTH && candidate.match?(/\A[0-9a-f]{64}\z/i)
    end

    def mutex
      @mutex ||= Mutex.new
    end
  end
end
