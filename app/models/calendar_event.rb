# frozen_string_literal: true

require "digest"

class CalendarEvent < ApplicationRecord
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable

  STATUS_VALUES = {
    confirmed: "confirmed",
    tentative: "tentative",
    cancelled: "cancelled",
  }.freeze

  MANUAL_SYNC_OVERRIDES = ["include", "exclude"].freeze

  # Columns only touched by sync bookkeeping; changes limited to these are not
  # worth an audit row.
  BOOKKEEPING_COLUMNS = [
    "source_updated_at",
    "synced_at",
    "updated_at",
    "last_synced_to_calendar",
    "fingerprint",
    "synced_fingerprint",
  ].freeze

  # Keys of `data` that never describe the event itself: volatile export
  # stamps and parser bookkeeping stored by older versions.
  IGNORED_DATA_KEYS = [
    "dtstamp",
    "last-modified",
    "created",
    "sequence",
    "uid",
    "summary",
    "description",
    "location",
    "status",
    "dtstart",
    "dtend",
  ].freeze

  belongs_to :calendar_source, inverse_of: :calendar_events

  # Override the association to bypass soft-delete scope, but respect eager loading.
  # Raises ActiveRecord::RecordNotFound when the source has been hard-deleted so
  # callers get a clear error instead of a confusing NoMethodError on nil.
  def calendar_source
    if association(:calendar_source).loaded?
      super
    else
      source = CalendarSource.unscoped.find_by(id: calendar_source_id)
      if source.nil? && calendar_source_id.present?
        raise ActiveRecord::RecordNotFound,
          "CalendarSource id=#{calendar_source_id} not found (hard-deleted?)"
      end
      source
    end
  end

  enum :status, STATUS_VALUES

  scope :upcoming, -> { where(starts_at: Time.current.beginning_of_day..).order(:starts_at) }
  scope :needs_sync, -> { where("synced_at IS NULL OR synced_at < source_updated_at") }
  # Cancelled events that may still exist in Apple Calendar (a delete failed or
  # never ran).
  scope :pending_remote_delete, -> { where(status: "cancelled").where.not(last_synced_to_calendar: nil) }

  validates :external_id, :title, :starts_at, :ends_at, :time_zone, presence: true
  # Uniqueness of (calendar_source_id, external_id) is enforced by a unique
  # index; the sync preloads events by external_id instead of validating.
  validates :manual_sync_override, inclusion: { in: MANUAL_SYNC_OVERRIDES }, allow_nil: true
  validates :all_day, inclusion: { in: [true, false] }
  validate :ensure_end_after_start
  validate :ensure_all_day_times_are_valid

  before_validation :assign_default_time_zone
  before_validation :sanitize_external_id
  before_save :refresh_fingerprint
  before_save :derive_sync_exempt
  after_commit :broadcast_change, on: [:create, :update], unless: -> { self.class.broadcasts_suppressed? }
  after_commit :broadcast_removal, on: :destroy, unless: -> { self.class.broadcasts_suppressed? }

  # Suppress per-event Turbo broadcasts during bulk operations (e.g., sync).
  # Callers should fire a single source-level broadcast after the batch completes.
  class << self
    def suppress_broadcasts
      Thread.current[:suppress_calendar_event_broadcasts] = true
      yield
    ensure
      Thread.current[:suppress_calendar_event_broadcasts] = false
    end

    def broadcasts_suppressed?
      Thread.current[:suppress_calendar_event_broadcasts] == true
    end
  end

  after_create_commit { audit!(:created) }
  after_update_commit { audit!(:updated) unless only_bookkeeping_changed? }
  after_destroy_commit { audit!(:deleted) }

  class << self
    # Mirrors the before_validation sanitisation so lookups by a raw feed UID
    # find the stored record.
    def sanitize_external_id(value)
      value.to_s.gsub(/[\r\n\t\0]/, "").strip
    end
  end

  def duration
    ends_at - starts_at
  end

  # Legacy writer: an explicit sync_exempt assignment is a manual decision.
  # It is stored as a manual override (or clears the override when it matches
  # what the filter rules would decide anyway).
  def sync_exempt=(value)
    exempt = ActiveModel::Type::Boolean.new.cast(value) || false
    self.manual_sync_override = if exempt == excluded_by_rule?
      nil
    else
      exempt ? "exclude" : "include"
    end
    super(exempt)
  end

  # Records a filter-rule decision without touching the manual override.
  def apply_rule_exclusion(excluded)
    self.excluded_by_rule = excluded
    self[:sync_exempt] = effective_sync_exempt?
  end

  def toggle_sync_exempt!
    update!(sync_exempt: !sync_exempt?)
  end

  # Effective exclusion: a manual override wins over filter rules.
  def effective_sync_exempt?
    case manual_sync_override
    when "exclude" then true
    when "include" then false
    else excluded_by_rule?
    end
  end

  # Digest of the event content as received from the feed. Bookkeeping and
  # volatile export data (DTSTAMP etc.) are excluded so that re-exporting an
  # unchanged feed produces the same fingerprint.
  def content_fingerprint
    payload = [
      title&.to_s&.encode("UTF-8", invalid: :replace, undef: :replace),
      description&.to_s&.encode("UTF-8", invalid: :replace, undef: :replace),
      location&.to_s&.encode("UTF-8", invalid: :replace, undef: :replace),
      starts_at&.utc&.iso8601,
      ends_at&.utc&.iso8601,
      all_day?,
      status,
      canonical_json(fingerprint_data),
    ].join("--")
    Digest::SHA256.hexdigest(payload)
  end

  def time_range
    starts_at..ends_at
  end

  def normalized_attributes
    {
      title: title,
      description: description,
      location: location,
      starts_at: starts_at.in_time_zone(time_zone),
      ends_at: ends_at.in_time_zone(time_zone),
      status: status,
      data: data,
    }
  end

  def mark_synced!
    update!(synced_at: Time.current)
  end

  def all_day?
    all_day
  end

  def duration_days
    return 0 unless all_day?

    (ends_at.to_date - starts_at.to_date).to_i
  end

  private

  def assign_default_time_zone
    self.time_zone = calendar_source&.time_zone || "UTC" if time_zone.blank?
  end

  # Strip newlines, tabs, and null bytes from external_id at ingestion time
  # to prevent ICS injection when the value is later used as a UID.
  def sanitize_external_id
    return if external_id.blank?

    self.external_id = self.class.sanitize_external_id(external_id)
  end

  def ensure_end_after_start
    return if ends_at.blank? || starts_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at < starts_at
  end

  def ensure_all_day_times_are_valid
    return unless all_day?
    return if starts_at.blank? || ends_at.blank?

    start_zone = starts_at.in_time_zone(time_zone)
    end_zone = ends_at.in_time_zone(time_zone)

    errors.add(:starts_at, "must be at beginning of day for all-day events") if start_zone.hour.nonzero? || start_zone.min.nonzero? || start_zone.sec.nonzero?

    return unless end_zone.hour.nonzero? || end_zone.min.nonzero? || end_zone.sec.nonzero?

    errors.add(:ends_at, "must be at beginning of day for all-day events")
  end

  def refresh_fingerprint
    self.fingerprint = content_fingerprint
  end

  def derive_sync_exempt
    self[:sync_exempt] = effective_sync_exempt?
  end

  def fingerprint_data
    (data || {}).to_h.stringify_keys.reject do |key, _value|
      IGNORED_DATA_KEYS.include?(key) || key.end_with?("_params", "_raw")
    end
  end

  def only_bookkeeping_changed?
    (previous_changes.keys - BOOKKEEPING_COLUMNS).empty?
  end

  # Produce a stable JSON string with recursively sorted keys so that
  # semantically identical data always generates the same fingerprint
  # regardless of key insertion order or Ruby version.
  def canonical_json(obj)
    case obj
    when Hash
      sorted = obj.sort_by { |k, _| k.to_s }.map { |k, v| [k, canonical_json(v)] }
      "{#{sorted.map { |k, v| "#{k.to_json}:#{v}" }.join(",")}}"
    when Array
      "[#{obj.map { |v| canonical_json(v) }.join(",")}]"
    when nil
      "null"
    else
      obj.to_json
    end
  end

  def broadcast_change
    broadcast_replace_later_to(
      "calendar_events",
      target: dom_id(self),
      partial: "calendar_events/calendar_event",
      locals: { calendar_event: self },
    )
  end

  def broadcast_removal
    broadcast_remove_to("calendar_events", target: dom_id(self))
  end

  def audit!(verb)
    changes_from = previous_changes.transform_values { |v| v.is_a?(Array) ? v.first : v }
    changes_to   = previous_changes.transform_values { |v| v.is_a?(Array) ? v.last : v }
    CalendarEventAudit.create!(
      calendar_event: self,
      action: verb,
      changes_from: changes_from,
      changes_to: changes_to,
      occurred_at: Time.current,
    )
  rescue StandardError => exception
    Rails.logger.warn("[Audit] Failed to record audit for event #{id}: #{exception.message}")
  end
end
