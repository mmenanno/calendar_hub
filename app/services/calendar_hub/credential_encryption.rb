# frozen_string_literal: true

require "digest"

module CalendarHub
  module CredentialEncryption
    extend self

    SALT = "calendar-source-salt"
    KEY_BYTES = 32
    HEX_LENGTH = KEY_BYTES * 2
    # Filesystems with coarse timestamps can give an in-place rewrite the same
    # mtime; within this window the key file's digest is compared as well.
    MTIME_GRANULARITY = 2 # seconds

    class KeyRotationError < StandardError; end

    # Raised for a stored ciphertext that neither the current key (re-read
    # from disk) nor the legacy key can decrypt.
    class DecryptionError < StandardError; end

    def encrypt(payload)
      hash = coerce_payload(payload)
      normalized = normalize_payload(hash)
      return if normalized.blank?

      current_encryptor.encrypt_and_sign(normalized.to_json)
    end

    def decrypt(ciphertext)
      return empty_hash if ciphertext.blank?

      encryptor = current_encryptor
      decrypted = decrypt_with(ciphertext, encryptor)
      if decrypted.nil?
        # The key may have been rotated by another process a moment ago.
        reloaded = reload_encryptor!
        decrypted = decrypt_with(ciphertext, reloaded) unless reloaded.equal?(encryptor)
      end
      decrypted || legacy_decrypt(ciphertext) || raise(DecryptionError, decryption_error_message)
    end

    def rotate!
      synchronize do
        refresh_key!
        old_encryptor = @current_encryptor
        new_key = generate_key
        new_encryptor = build_encryptor(new_key)

        ActiveRecord::Base.transaction do
          reencrypt_calendar_sources(old_encryptor, new_encryptor)
          reencrypt_app_settings(old_encryptor, new_encryptor)
          write_key(new_key) # Must be inside transaction so a filesystem failure rolls back re-encrypted credentials
        end
        install_key(new_key)
      end
    rescue StandardError => exception
      reset_cached_encryptor!
      remove_instance_variable(:@legacy_encryptor) if instance_variable_defined?(:@legacy_encryptor)
      raise KeyRotationError, exception.message
    end

    # Returns the current key, (re)loading it when the key file changed since
    # it was read (e.g. rotated by another process) and generating one when
    # none exists yet.
    def ensure_key!
      synchronize { refresh_key! }
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
      generated_at = key_store.credential_key_generated_at
      generated_at ||= path.exist? ? path.stat.mtime : nil
      {
        fingerprint: key_fingerprint,
        path: path.to_s,
        created_at: generated_at,
      }
    end

    def reset!
      synchronize do
        reset_cached_encryptor!
        remove_instance_variable(:@legacy_encryptor) if instance_variable_defined?(:@legacy_encryptor)
        remove_instance_variable(:@key_store) if instance_variable_defined?(:@key_store)
        CalendarHub::KeyStore.reset!
      end
    end

    private

    def reset_cached_encryptor!
      [:@current_key, :@current_encryptor, :@key_signature, :@key_digest, :@key_verified_at].each do |ivar|
        remove_instance_variable(ivar) if instance_variable_defined?(ivar)
      end
    end

    # Callers must hold the mutex.
    def refresh_key!
      load_key! unless key_loaded? && !key_file_changed?
      @current_key
    end

    def reload_encryptor!
      synchronize do
        load_key!
        @current_encryptor
      end
    end

    def load_key!
      # Fresh instance: KeyStore caches the document it read.
      @key_store = CalendarHub::KeyStore.instance
      # A deleted key file keeps the loaded key rather than minting a new one
      # that no stored credential was encrypted with.
      return if key_loaded? && !key_path.exist?

      # Remember the file as it was *before* reading, so a write racing with
      # the read is noticed on the next call.
      signature = key_file_signature
      digest = key_file_digest
      key = @key_store.credential_key
      if valid_key?(key)
        install_key(key, signature: signature, digest: digest)
      else
        install_key(generate_and_store_key)
      end
    end

    def install_key(key, signature: key_file_signature, digest: key_file_digest)
      # Deriving the encryptor is deliberately slow (PBKDF2); skip it when a
      # reload finds the same key.
      @current_encryptor = build_encryptor(key) unless key == @current_key && @current_encryptor
      @current_key = key
      @key_signature = signature
      @key_digest = digest
      @key_verified_at = Time.current
    end

    def key_loaded?
      instance_variable_defined?(:@current_key) && @current_key.present?
    end

    # Cheap check (one stat) run before every encrypt/decrypt.
    def key_file_changed?
      signature = key_file_signature
      return false if signature.nil? # file deleted: keep the loaded key
      return true if signature != @key_signature

      _dev, _ino, _size, mtime = signature
      return false if mtime < @key_verified_at - MTIME_GRANULARITY
      return true if key_file_digest != @key_digest

      @key_verified_at = Time.current
      false
    end

    def key_file_signature
      stat = key_path.stat
      [stat.dev, stat.ino, stat.size, stat.mtime]
    rescue Errno::ENOENT
      nil
    end

    def key_file_digest
      Digest::SHA256.file(key_path).hexdigest
    rescue Errno::ENOENT
      nil
    end

    def decryption_error_message
      "Stored credentials can't be decrypted: the credential key in #{key_path} doesn't match the one they were " \
        "encrypted with. Restore #{key_path.basename} from a backup, or re-enter the credentials."
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
      rescue StandardError
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
      synchronize do
        refresh_key!
        @current_encryptor
      end
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

      key_store.write_credential_key!(key)
    end

    def read_key
      key = key_store.credential_key
      raise ArgumentError, "Invalid key length" unless valid_key?(key)

      key
    end

    def key_path
      key_store.store_path
    end

    def generate_key
      SecureRandom.hex(KEY_BYTES)
    end

    def valid_key?(candidate)
      candidate.is_a?(String) && candidate.present? && candidate.length == HEX_LENGTH && candidate.match?(/\A[0-9a-f]{64}\z/i)
    end

    MUTEX = Mutex.new
    private_constant :MUTEX

    # Reentrant: rotate! reloads the key while already holding the lock.
    def synchronize(&)
      MUTEX.owned? ? yield : MUTEX.synchronize(&)
    end

    def key_store
      @key_store ||= CalendarHub::KeyStore.instance
    end
  end
end
