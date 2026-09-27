# frozen_string_literal: true

class FilterRule < ApplicationRecord
  MATCH_TYPES = {
    contains: "contains",
    equals: "equals",
    regex: "regex",
  }.freeze

  FIELD_NAMES = {
    title: "title",
    description: "description",
    location: "location",
  }.freeze

  belongs_to :calendar_source, optional: true

  enum :match_type, MATCH_TYPES
  enum :field_name, FIELD_NAMES

  scope :active, -> { where(active: true) }
  default_scope { order(position: :asc, created_at: :asc) }

  validates :match_type, inclusion: { in: MATCH_TYPES.values }
  validates :field_name, inclusion: { in: FIELD_NAMES.values }
  validates :pattern, presence: true

  after_commit :schedule_filter_sync

  def matches?(event)
    return false unless active?

    field_value = case field_name
    when "title"
      event.title
    when "description"
      event.description
    when "location"
      event.location
    else
      return false
    end

    return false if field_value.blank?

    case match_type
    when "equals"
      compare?(field_value, pattern, case_sensitive: case_sensitive, mode: :equals)
    when "contains"
      compare?(field_value, pattern, case_sensitive: case_sensitive, mode: :contains)
    when "regex"
      CalendarHub::SafeRegexp.match?(compiled_regex, field_value)
    else
      false
    end
  end

  private

  # Compiled once per pattern/case setting (with a match timeout).
  def compiled_regex
    key = [pattern, case_sensitive]
    return @compiled_regex if @compiled_regex_key == key

    @compiled_regex_key = key
    @compiled_regex = CalendarHub::SafeRegexp.compile(pattern, case_sensitive: case_sensitive)
  end

  def compare?(text, pattern, case_sensitive:, mode:)
    a = text.to_s
    b = pattern.to_s
    unless case_sensitive
      a = a.downcase
      b = b.downcase
    end
    case mode
    when :equals
      a == b
    when :contains
      a.include?(b)
    else
      false
    end
  end

  def schedule_filter_sync
    return if only_position_changed?

    if destroyed?
      # Skip if the source itself was destroyed (cascading delete)
      return if calendar_source_id && !CalendarSource.exists?(calendar_source_id)

      SyncFilterRulesJob.perform_later(calendar_source_id: calendar_source_id)
    else
      SyncFilterRulesJob.perform_later(id)
    end
  end

  def only_position_changed?
    return false if destroyed?

    saved_changes.except("position", "updated_at").empty?
  end
end
