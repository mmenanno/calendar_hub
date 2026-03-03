# frozen_string_literal: true

class EventMapping < ApplicationRecord
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

  after_destroy :clear_name_mapper_cache
  after_save :clear_name_mapper_cache
  after_commit :schedule_affected_syncs

  def has_destination_override?
    target_calendar_identifier.present?
  end

  private

  def must_have_replacement_or_destination
    if replacement.blank? && target_calendar_identifier.blank?
      errors.add(:base, "must have a replacement or a destination calendar override")
    end
  end

  def clear_name_mapper_cache
    cache_key = "name_mapper/active_mappings/#{calendar_source_id || "global"}"
    Rails.cache.delete(cache_key)
  end

  def schedule_affected_syncs
    return if only_position_changed?

    affected_sources.select(&:syncable?).each { |source| SyncCalendarJob.perform_later(source.id) }
  end

  def affected_sources
    if calendar_source_id
      source = CalendarSource.find_by(id: calendar_source_id)
      source ? [source] : []
    else
      CalendarSource.active.to_a
    end
  end

  def only_position_changed?
    return false if destroyed?

    saved_changes.except("position", "updated_at").empty?
  end
end
