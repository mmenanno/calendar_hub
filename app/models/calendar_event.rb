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

  belongs_to :calendar_source

  enum :status, STATUS_VALUES

  scope :upcoming, -> { where(starts_at: Time.current.beginning_of_day..).order(:starts_at) }
  scope :needs_sync, -> { where("synced_at IS NULL OR synced_at < source_updated_at") }

  validates :external_id, :title, :starts_at, :ends_at, :time_zone, presence: true
  validates :external_id, uniqueness: { scope: :calendar_source_id }
  validate :ensure_end_after_start

  before_validation :assign_default_time_zone
  before_save :refresh_fingerprint
  after_commit :broadcast_change, on: [:create, :update]
  after_commit :broadcast_removal, on: :destroy
  after_create_commit { audit!(:created) }
  after_update_commit { audit!(:updated) }
  after_destroy_commit { audit!(:deleted) }

  def duration
    ends_at - starts_at
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

  private

  def assign_default_time_zone
    self.time_zone = calendar_source&.time_zone || "UTC" if time_zone.blank?
  end

  def ensure_end_after_start
    return if ends_at.blank? || starts_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at < starts_at
  end

  def refresh_fingerprint
    payload = [
      title,
      description,
      location,
      starts_at.utc.iso8601,
      ends_at.utc.iso8601,
      status,
      data.to_s,
    ].join("--")
    self.fingerprint = Digest::SHA256.hexdigest(payload)
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
  rescue => e
    Rails.logger.warn("[Audit] Failed to record audit for event #{id}: #{e.message}")
  end
end
