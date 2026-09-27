# frozen_string_literal: true

class EventMapping < ApplicationRecord
  include RegexPatternValidation

  MATCH_TYPES = {
    contains: "contains",
    equals: "equals",
    regex: "regex",
  }.freeze

  belongs_to :calendar_source, optional: true

  enum :match_type, MATCH_TYPES

  scope :active, -> { where(active: true) }
  default_scope { order(position: :asc, created_at: :asc) }

  validates :match_type, inclusion: { in: MATCH_TYPES.values }
  validates :pattern, presence: true
  validates :replacement, presence: true, unless: -> { target_calendar_identifier.present? }
  validate :must_have_replacement_or_destination

  after_commit :reset_name_mapper_cache
  after_commit :schedule_affected_syncs

  def destination_override?
    target_calendar_identifier.present?
  end

  private

  def must_have_replacement_or_destination
    return unless replacement.blank? && target_calendar_identifier.blank?

    errors.add(:base, "must have a replacement or a destination calendar override")
  end

  # NameMapper memoizes mappings per request/job; drop them once a change is
  # committed so the rest of this request sees it.
  def reset_name_mapper_cache
    CalendarHub::NameMapper.reset_cache!
  end

  # Mapping changes affect titles/destinations of already-synced events, so
  # re-sync affected sources through the normal scheduling path (which
  # creates a SyncAttempt and respects the one-active-sync-per-source rule).
  # A sync only re-pushes events whose mapped payload actually changed.
  def schedule_affected_syncs
    return if only_position_changed?

    affected_sources.select(&:syncable?).each { |source| source.schedule_sync(force: true, full: false) }
  end

  # Includes the previous source when a mapping moved between sources.
  def affected_sources
    source_ids = [calendar_source_id]
    source_ids << previous_changes["calendar_source_id"].first if !previously_new_record? && previous_changes.key?("calendar_source_id")
    source_ids.uniq!
    return CalendarSource.active.to_a if source_ids.include?(nil)

    CalendarSource.where(id: source_ids).to_a
  end

  def only_position_changed?
    return false if destroyed?

    saved_changes.except("position", "updated_at").empty?
  end
end
