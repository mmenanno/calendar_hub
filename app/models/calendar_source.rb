# frozen_string_literal: true

class CalendarSource < ApplicationRecord
  has_many :calendar_events, dependent: :destroy
  has_many :sync_attempts, dependent: :destroy
  has_one :latest_sync_attempt, -> { order(created_at: :desc) }, class_name: "SyncAttempt"
  has_many :sync_metrics, dependent: :destroy
  has_many :event_mappings, dependent: :destroy
  has_many :filter_rules, dependent: :destroy

  scope :active, -> { where(active: true) }
  scope :auto_sync_enabled, -> { where(auto_sync_enabled: true) }
  scope :failing, -> { where("consecutive_sync_failures >= 1") }
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
    return unless force || within_sync_window?

    # Mark stale active attempts as failed so they don't block new syncs
    sync_attempts
      .where(status: ["queued", "running"])
      .where("created_at < ?", 2.hours.ago)
      .update_all(status: "failed", finished_at: Time.current, message: "Marked failed: stale attempt")

    # Rely on the DB unique partial index (idx_unique_active_sync_attempt_per_source)
    # to prevent duplicate active attempts. If another thread already created one,
    # the insert will raise RecordNotUnique and we safely return nil.
    attempt = SyncAttempt.create!(calendar_source: self, status: :queued)
    SyncCalendarJob.perform_later(id, attempt_id: attempt.id)
    attempt
  rescue ActiveRecord::RecordNotUnique
    # Another worker already has an active sync for this source -- that's fine.
    nil
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
    mappings_data = event_mappings.active.order(:position).pluck(:pattern, :replacement, :match_type, :case_sensitive)
    settings_data = [sync_frequency_minutes, sync_window_start_hour, sync_window_end_hour, time_zone]
    Digest::SHA256.hexdigest([mappings_data, settings_data].inspect)
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

  def record_sync_success!
    update!(consecutive_sync_failures: 0)
  end

  def record_sync_failure!
    self.consecutive_sync_failures ||= 0
    increment!(:consecutive_sync_failures)
  end

  def healthy?
    consecutive_sync_failures.to_i.zero?
  end

  def health_status
    count = consecutive_sync_failures.to_i
    case count
    when 0
      :healthy
    when 1..2
      :warning
    else
      :error
    end
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
