# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :default_time_zone, presence: true
  validates :default_sync_frequency_minutes, presence: true, numericality: { greater_than: 0 }
  validates :singleton_guard, inclusion: { in: [0] }

  before_validation :persist_credentials
  after_commit :reset_credential_store!, on: [:create, :update]
  after_commit :invalidate_instance_cache!, on: [:create, :update]

  # Holds the settings row for the current request or job. Rails resets
  # CurrentAttributes around every request and job (via the executor), so a
  # change saved in the web process reaches Solid Queue workers on their next
  # job instead of never. It's also per thread, so Puma threads don't share
  # (and mutate) one record.
  class Memo < ActiveSupport::CurrentAttributes
    attribute :setting
  end

  class << self
    def instance
      Memo.setting ||= begin
        first || create!(default_time_zone: "UTC", default_sync_frequency_minutes: 60)
      rescue ActiveRecord::RecordNotUnique
        first
      end
    end

    def reset_instance!
      Memo.setting = nil
    end
  end

  def apple_username
    credential_store[:apple_username]
  end

  def apple_username=(value)
    upsert_credential(:apple_username, value)
  end

  def apple_app_password
    credential_store[:apple_app_password]
  end

  def apple_app_password=(value)
    upsert_credential(:apple_app_password, value)
  end

  # True when stored Apple credentials exist but can't be decrypted with the
  # current credential key (see CredentialEncryption::DecryptionError).
  def credentials_unreadable?
    credential_store
    @credentials_unreadable == true
  end

  def credentials_decryption_error
    @credentials_decryption_error if credentials_unreadable?
  end

  # Explicitly forgets the Apple credentials, including unreadable ones.
  def clear_apple_credentials
    @credential_store = {}.with_indifferent_access
    @credentials_assigned = true
  end

  def credential_key_fingerprint
    CalendarHub::CredentialEncryption.key_fingerprint
  end

  def rotate_credentials_key!
    plaintext = credential_store.deep_dup
    CalendarHub::CredentialEncryption.rotate!
    reload
    reset_credential_store!

    return if plaintext.blank?

    plaintext.each { |key, value| upsert_credential(key, value) }
    persist_credentials
    save!(validate: false)
  end

  private

  def credential_store
    @credential_store ||= begin
      @credentials_unreadable = false
      data = if apple_credentials_ciphertext.present?
        decrypt_credentials
      else
        legacy_payload
      end
      data.with_indifferent_access
    end
  end

  def decrypt_credentials
    CalendarHub::CredentialEncryption.decrypt(apple_credentials_ciphertext)
  rescue CalendarHub::CredentialEncryption::DecryptionError => exception
    @credentials_unreadable = true
    @credentials_decryption_error = exception
    {}
  end

  def legacy_payload
    {}.tap do |memo|
      username = sanitize(self[:apple_username])
      password = sanitize(self[:apple_app_password])
      memo[:apple_username] = username if username.present?
      memo[:apple_app_password] = password if password.present?
    end
  end

  def upsert_credential(key, raw_value)
    sanitized = sanitize(raw_value)
    if sanitized.present?
      credential_store[key] = sanitized
      @credentials_assigned = true
    else
      credential_store.delete(key)
    end
  end

  def sanitize(value)
    return if value.nil?
    return value unless value.is_a?(String)

    value.strip.presence
  end

  def persist_credentials
    return unless instance_variable_defined?(:@credential_store)
    # Unreadable credentials are only replaced by newly entered ones: blank
    # form fields must not wipe a ciphertext that restoring the key store
    # from a backup would make readable again.
    return if credentials_unreadable? && !@credentials_assigned

    normalized = credential_store.each_with_object({}) do |(key, value), memo|
      sanitized = sanitize(value)
      memo[key] = sanitized if sanitized.present?
    end

    if normalized.present?
      self.apple_credentials_ciphertext = CalendarHub::CredentialEncryption.encrypt(normalized)
    elsif attribute_present?(:apple_credentials_ciphertext)
      self.apple_credentials_ciphertext = nil
    end

    self[:apple_username] = nil if attribute_present?(:apple_username)
    self[:apple_app_password] = nil if attribute_present?(:apple_app_password)
  end

  def reset_credential_store!
    [:@credential_store, :@credentials_unreadable, :@credentials_decryption_error, :@credentials_assigned].each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end
  end

  def invalidate_instance_cache!
    self.class.reset_instance!
  end
end
