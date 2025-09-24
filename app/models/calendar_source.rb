# frozen_string_literal: true

class CalendarSource < ApplicationRecord
  has_many :calendar_events, dependent: :destroy
  has_many :sync_attempts, dependent: :destroy

  scope :active, -> { where(active: true) }
  default_scope -> { where(deleted_at: nil) }

  store_accessor :settings, :time_zone, :default_status

  validates :name, presence: true
  validates :calendar_identifier, presence: true
  validates :ingestion_url, presence: true, if: :requires_ingestion_url?
  validates :sync_window_start_hour, :sync_window_end_hour, allow_nil: true, inclusion: { in: 0..23 }

  def time_zone
    super.presence || AppSetting.instance.default_time_zone || "UTC"
  end

  def schedule_sync(force: false)
    return unless syncable?
    # Avoid double-queueing if an attempt is already queued or running
    return if sync_attempts.exists?(status: ["queued", "running"])
    return unless force || within_sync_window?

    attempt = SyncAttempt.create!(calendar_source: self, status: :queued)
    SyncCalendarJob.perform_later(id, attempt_id: attempt.id)
    attempt
  end

  def mark_synced!(token:, timestamp: Time.current)
    update!(sync_token: token, last_synced_at: timestamp)
  end

  def translator
    CalendarHub::Translators::EventTranslator.new(self)
  end

  def ingestion_adapter
    CalendarHub::Ingestion::GenericIcsAdapter.new(self)
  end

  def syncable?
    active? && ingestion_adapter.present?
  end

  def soft_delete!
    update!(active: false, deleted_at: Time.current)
  end

  def within_sync_window?(now: Time.current)
    return true if sync_window_start_hour.nil? || sync_window_end_hour.nil?

    tz_now = now.in_time_zone(time_zone)
    start_h = sync_window_start_hour
    end_h   = sync_window_end_hour
    if start_h <= end_h
      (start_h..end_h).cover?(tz_now.hour)
    else
      # window wraps midnight, e.g., 22 -> 2
      tz_now.hour >= start_h || tz_now.hour <= end_h
    end
  end

  def next_sync_time(now: Time.current)
    return now if sync_window_start_hour.nil? || sync_window_end_hour.nil?

    tz = ActiveSupport::TimeZone[time_zone] || Time.zone
    tz_now = now.in_time_zone(tz)
    start_h = sync_window_start_hour
    end_h   = sync_window_end_hour

    # If already within window, next is now
    return tz_now if within_sync_window?(now: now)

    # Compute the next start time in tz
    next_start = tz_now.change(hour: start_h, min: 0, sec: 0)
    if start_h <= end_h
      next_start += 1.day if tz_now.hour > end_h || tz_now.hour >= start_h
      next_start = tz_now.change(hour: start_h) if tz_now.hour < start_h
      next_start
    else
      # Window wraps midnight; start_h..24 or 0..end_h
      # If we're before start_h, today at start_h; otherwise, tomorrow at start_h
      tz_now.hour < start_h ? next_start : next_start + 1.day
    end
  end

  def pending_events_count
    calendar_events.needs_sync.count
  end

  def credentials=(value)
    write_attribute(:credentials, encrypt_payload(value))
  end

  def credentials
    decrypted = read_attribute(:credentials)
    decrypt_payload(decrypted)
  end

  private

  def requires_ingestion_url?
    true
  end

  def encrypt_payload(value)
    normalized = (value || {}).each_with_object({}) do |(key, val), memo|
      next if val.blank?

      memo[key.to_s] = val
    end
    return if normalized.blank?

    self.class.credential_encryptor.encrypt_and_sign(normalized.to_json)
  end

  def decrypt_payload(ciphertext)
    return {}.with_indifferent_access if ciphertext.blank?

    JSON.parse(self.class.credential_encryptor.decrypt_and_verify(ciphertext)).with_indifferent_access
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    {}.with_indifferent_access
  end

  class << self
    def credential_encryptor
      key = credential_key_material
      salt = credential_salt
      secret = ActiveSupport::KeyGenerator.new(key).generate_key(salt, ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(secret, cipher: "aes-256-gcm")
    end

    private

    def credential_key_material
      Rails.application.credentials.dig(:calendar_hub, :credential_encryption_key) || ENV.fetch("CREDENTIAL_ENCRYPTION_KEY", nil) || default_key_material
    end

    def credential_salt
      Rails.application.credentials.dig(:calendar_hub, :credential_encryption_salt) || ENV.fetch("CREDENTIAL_ENCRYPTION_SALT", "calendar-source-salt")
    end

    def default_key_material
      Rails.application.key_generator.generate_key("calendar_source_credentials", ActiveSupport::MessageEncryptor.key_len)
    end
  end
end
