# frozen_string_literal: true

# Daily snapshot of the SQLite databases and key store (see CalendarHub::Backup).
class BackupJob < ApplicationJob
  queue_as :default

  def perform
    with_error_tracking(context: "backup") do
      path = CalendarHub::Backup.run
      Rails.logger.info("[BackupJob] Backup written to #{path}")
      path.to_s
    end
  end
end
