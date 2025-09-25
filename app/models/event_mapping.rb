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
  validates :pattern, :replacement, presence: true
end
