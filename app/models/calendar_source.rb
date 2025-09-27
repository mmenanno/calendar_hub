# frozen_string_literal: true

class CalendarSource < ApplicationRecord
  has_many :calendar_events, dependent: :destroy
  has_many :sync_attempts, dependent: :destroy
  has_many :event_mappings, dependent: :destroy
  has_many :filter_rules, dependent: :destroy

  scope :active, -> { where(active: true) }
  scope :auto_sync_enabled, -> { where(auto_sync_enabled: true) }
  default_scope -> { where(deleted_at: nil) }

  store_accessor :settings, :time_zone, :default_status

  validates :name, presence: true
  validates :calendar_identifier, presence: true
  validates :ingestion_url, presence: true, if: :requires_ingestion_url?
  validates :sync_window_start_hour, :sync_window_end_hour, allow_nil: true, inclusion: { in: 0..23 }
  validates :sync_frequency_minutes, allow_nil: true, numericality: { greater_than: 0 }

  before_create :set_import_start_date

  def time_zone
    super.presence || AppSetting.instance.default_time_zone || "UTC"
  end

  def sync_frequency_minutes
    super.presence || AppSetting.instance.default_sync_frequency_minutes
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

  def translator
    CalendarHub::Translators::EventTranslator.new(self)
  end

  def ingestion_adapter
    CalendarHub::Ingestion::GenericICSAdapter.new(self)
  end

  def syncable?
    active? && ingestion_adapter.present?
  end

  def auto_syncable?
    auto_sync_enabled? && syncable?
  end

  def sync_due?(now: Time.current)
    return false unless auto_syncable?
    return true if last_synced_at.nil?

    last_synced_at <= now - sync_frequency_minutes.minutes
  end

  def next_auto_sync_time(now: Time.current)
    return unless auto_syncable?

    base_time = last_synced_at&.+(sync_frequency_minutes.minutes) || now

    return now if within_sync_window?(now: now) && base_time <= now

    next_sync_time(now: [base_time, now].max)
  end

  def generate_change_hash
    mappings_hash = event_mappings.active.order(:position).pluck(:pattern, :replacement, :match_type, :case_sensitive).hash
    settings_hash = [sync_frequency_minutes, sync_window_start_hour, sync_window_end_hour, time_zone].hash
    [mappings_hash, settings_hash].hash.to_s
  end

  def mark_synced!(token:, timestamp: Time.current)
    update!(
      sync_token: token,
      last_synced_at: timestamp,
      last_change_hash: generate_change_hash,
    )
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

  def set_import_start_date
    self.import_start_date ||= Time.current
  end

  def encrypt_payload(value)
    CalendarHub::CredentialEncryption.encrypt(value)
  end

  def decrypt_payload(ciphertext)
    CalendarHub::CredentialEncryption.decrypt(ciphertext)
  end
end
