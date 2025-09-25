# frozen_string_literal: true

class SyncEventResult < ApplicationRecord
  belongs_to :sync_attempt
  belongs_to :calendar_event, optional: true

  scope :failures, -> { where(success: false) }
end
