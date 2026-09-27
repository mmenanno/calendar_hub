# frozen_string_literal: true

namespace :calendar_hub do
  desc "Snapshot the SQLite databases and key store (CALENDAR_HUB_BACKUP_DIR, CALENDAR_HUB_BACKUP_KEEP)"
  task backup: :environment do
    path = CalendarHub::Backup.run
    puts "Backup written to #{path}"
  end
end
