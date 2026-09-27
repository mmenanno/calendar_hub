# frozen_string_literal: true

class CalendarSource < ApplicationRecord
  has_many :calendar_events, dependent: :destroy
  has_many :sync_attempts, dependent: :destroy
  # Do not `includes(:latest_sync_attempt)`: has_one preloading applies no
  # per-owner LIMIT, so it loads every attempt of every source. Use
  # CalendarSource.preload_latest_sync_attempts instead.
  has_one :latest_sync_attempt, -> { order(created_at: :desc, id: :desc) }, class_name: "SyncAttempt", inverse_of: false, dependent: nil
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

  before_validation :normalize_ingestion_url
  before_create :set_import_start_date

  class << self
    # Loads the latest sync attempt for each source with two indexed queries
    # (one LIMIT 1 seek per source, then the attempts by primary key) and
    # assigns it to the latest_sync_attempt association. Returns an array.
    def preload_latest_sync_attempts(sources)
      sources = sources.to_a
      return sources if sources.empty?

      attempt_ids = latest_sync_attempt_ids(unscoped.where(id: sources.map(&:id)))
      attempts = SyncAttempt.where(id: attempt_ids).index_by(&:calendar_source_id)

      sources.each { |source| source.association(:latest_sync_attempt).target = attempts[source.id] }
    end

    # Ids of the latest sync attempt of each source in `sources` (sources
    # without attempts are skipped).
    def latest_sync_attempt_ids(sources = unscoped)
      latest_id = SyncAttempt
        .where("sync_attempts.calendar_source_id = calendar_sources.id")
        .order(created_at: :desc, id: :desc)
        .limit(1)
        .select(:id)
      sources.pluck(Arel.sql("(#{latest_id.to_sql})")).compact
    end
  end

  def time_zone
    super.presence || AppSetting.instance.default_time_zone || "UTC"
  end

  def sync_frequency_minutes
    super.presence || AppSetting.instance.default_sync_frequency_minutes
  end

  # Upper bound for the retry delay of a failing source.
  MAX_SYNC_BACKOFF = 24.hours
  BACKOFF_EXPONENT_CAP = 5

  # force: ignore the sync window.
  # full:  fetch the feed unconditionally and re-push every event (the
  #        "Force Sync" button). Defaults to force; callers that only need
  #        pending changes pushed (mapping/filter edits) pass full: false.
  # trigger: "manual" (user action) or "auto" (scheduler), shown on the jobs page.
  def schedule_sync(force: false, full: force, trigger: "manual")
    return unless syncable?
    return unless force || within_sync_window?

    # Mark stale active attempts (no progress heartbeat for 2h) as failed so
    # they don't block new syncs.
    sync_attempts.stale
      .update_all(status: "failed", finished_at: Time.current, message: "Marked failed: stale attempt") # rubocop:disable Rails/SkipsModelValidations -- bookkeeping write, no callbacks wanted

    # Rely on the DB unique partial index (idx_unique_active_sync_attempt_per_source)
    # to prevent duplicate active attempts. If another thread already created one,
    # the insert will raise RecordNotUnique and we safely return nil.
    attempt = SyncAttempt.create!(calendar_source: self, status: :queued, trigger: trigger)
    job_options = { attempt_id: attempt.id }
    job_options[:force] = true if full
    job = SyncCalendarJob.perform_later(id, **job_options)
    attempt.update_column(:job_id, job.job_id) if job.respond_to?(:job_id) # rubocop:disable Rails/SkipsModelValidations -- bookkeeping write, no callbacks wanted
    attempt
  rescue ActiveRecord::RecordNotUnique
    # Another worker already has an active sync for this source -- that's fine.
    nil
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

    due_at = next_sync_due_at
    due_at.nil? || due_at <= now
  end

  # When the next automatic sync is due. A source whose last sync failed
  # backs off exponentially (frequency * 2^failures, capped at 24h) from the
  # last attempt instead of being refetched every scheduler tick.
  def next_sync_due_at
    if sync_backing_off?
      reference = last_sync_attempt_at || last_synced_at
      reference && (reference + sync_backoff_interval)
    else
      last_synced_at&.+(sync_frequency_minutes.minutes)
    end
  end

  def sync_backoff_interval
    exponent = [consecutive_sync_failures.to_i, BACKOFF_EXPONENT_CAP].min
    [sync_frequency_minutes.minutes * (2**exponent), MAX_SYNC_BACKOFF].min
  end

  def next_auto_sync_time(now: Time.current)
    return unless auto_syncable?

    base_time = next_sync_due_at || now

    return now if within_sync_window?(now: now) && base_time <= now

    next_sync_time(now: [base_time, now].max)
  end

  # Configuration that affects how feed data is interpreted or pushed. When it
  # differs from last_change_hash the next sync refetches the feed fully.
  def generate_change_hash
    mappings_data = EventMapping.active.where(calendar_source_id: [nil, id]).reorder(:calendar_source_id, :position, :id)
      .pluck(:calendar_source_id, :pattern, :replacement, :match_type, :case_sensitive, :target_calendar_identifier)
    settings_data = [sync_frequency_minutes, sync_window_start_hour, sync_window_end_hour, time_zone]
    Digest::SHA256.hexdigest([mappings_data, settings_data].inspect)
  end

  # Called once a sync completed. Feed cache validators (ETag /
  # Last-Modified) are only stored here, so a failed sync never makes the next
  # run skip the feed with a 304.
  def mark_synced!(token:, timestamp: Time.current, cache_headers: nil)
    attributes = {
      sync_token: token,
      last_synced_at: timestamp,
      last_change_hash: generate_change_hash,
    }
    if cache_headers
      attributes[:settings] = settings.to_h.merge(
        "etag" => cache_headers[:etag],
        "last_modified" => cache_headers[:last_modified],
      ).compact
      attributes[:ics_feed_etag] = cache_headers[:etag]
      attributes[:ics_feed_last_modified] = cache_headers[:last_modified]
    end
    update!(attributes)
  end

  # Archiving also removes the source's events from Apple Calendar (in the
  # background); the local rows are kept so the source can be restored.
  def soft_delete!
    update!(active: false, deleted_at: Time.current)
    RemoveSourceEventsFromAppleJob.perform_later(id)
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

  # Backoff applies when the latest attempt failed outright; a sync that
  # completed with a few per-event errors keeps the normal cadence.
  def sync_backing_off?
    consecutive_sync_failures.to_i.positive? && latest_finished_sync_attempt&.failed?
  end

  def record_sync_failure!
    self.consecutive_sync_failures ||= 0
    increment!(:consecutive_sync_failures) # rubocop:disable Rails/SkipsModelValidations -- bookkeeping write, no callbacks wanted
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

  def latest_finished_sync_attempt
    sync_attempts.where.not(finished_at: nil).reorder(finished_at: :desc).first
  end

  def last_sync_attempt_at
    latest_finished_sync_attempt&.finished_at
  end

  def requires_ingestion_url?
    true
  end

  def normalize_ingestion_url
    return if ingestion_url.blank?

    self.ingestion_url = CalendarHub::Shared::HttpClient.normalize_url(ingestion_url)
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
