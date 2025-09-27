# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :default_time_zone, presence: true
  validates :default_sync_frequency_minutes, presence: true, numericality: { greater_than: 0 }

  before_validation :persist_credentials
  after_commit :reset_credential_store!, on: [:create, :update]

  class << self
    def instance
      first_or_create!(default_time_zone: "UTC", default_sync_frequency_minutes: 60)
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

  def credential_key_fingerprint
    CalendarHub::CredentialEncryption.key_fingerprint
  end

  def rotate_credentials_key!
    plaintext = credential_store.deep_dup
    CalendarHub::CredentialEncryption.rotate!
    reload
    reset_credential_store!

    if plaintext.present?
      plaintext.each { |key, value| upsert_credential(key, value) }
      persist_credentials
      save!(validate: false)
    end
  end

  private

  def credential_store
    @credential_store ||= begin
      data = if apple_credentials_ciphertext.present?
        CalendarHub::CredentialEncryption.decrypt(apple_credentials_ciphertext)
      else
        legacy_payload
      end
      data.with_indifferent_access
    end
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
    remove_instance_variable(:@credential_store) if instance_variable_defined?(:@credential_store)
  end
end
