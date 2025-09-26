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

  after_destroy :clear_name_mapper_cache
  after_save :clear_name_mapper_cache

  private

  def clear_name_mapper_cache
    cache_key = "name_mapper/active_mappings/#{calendar_source_id || "global"}"
    Rails.cache.delete(cache_key)
  end
end
