# frozen_string_literal: true

require "test_helper"
require "rake"

class BackupJobTest < ActiveJob::TestCase
  test "runs a backup and returns its path" do
    CalendarHub::Backup.expects(:run).returns(Pathname.new("/backups/calendar_hub-20260101-030000"))

    assert_equal("/backups/calendar_hub-20260101-030000", BackupJob.perform_now)
  end

  test "re-raises backup failures" do
    CalendarHub::Backup.expects(:run).raises(SQLite3::Exception, "disk full")

    assert_raises(SQLite3::Exception) { BackupJob.perform_now }
  end

  test "calendar_hub:backup rake task runs a backup" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("calendar_hub:backup")
    CalendarHub::Backup.expects(:run).returns(Pathname.new("/backups/snap"))

    assert_output(%r{Backup written to /backups/snap}) do
      Rake::Task["calendar_hub:backup"].execute
    end
  end
end
