# frozen_string_literal: true

# Dismissing a sync-failure banner records when it was acknowledged instead of
# resetting consecutive_sync_failures. The banner stays hidden until a newer
# failed attempt occurs.
class AddFailureAcknowledgedAtToCalendarSources < ActiveRecord::Migration[8.1]
  def change
    add_column(:calendar_sources, :failure_acknowledged_at, :datetime)
  end
end
