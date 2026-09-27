# frozen_string_literal: true

# Records what started a sync attempt ("manual" or "auto") so the admin Jobs
# page no longer infers it from the source's current auto-sync setting.
# Existing rows stay NULL (unknown).
class AddTriggerToSyncAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column(:sync_attempts, :trigger, :string)
  end
end
