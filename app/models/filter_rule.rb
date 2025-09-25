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
      begin
        flags = case_sensitive ? nil : Regexp::IGNORECASE
        re = Regexp.new(pattern, flags)
        !!(field_value =~ re)
      rescue RegexpError
        false
      end
    else
      false
    end
  end

  private

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
end
