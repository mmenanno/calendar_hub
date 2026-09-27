# frozen_string_literal: true

class PurgeCalendarSourceJob < ApplicationJob
  queue_as :sync

  # iCloud deletes are retried; if they keep failing the rows are purged
  # anyway (the failure is logged) rather than keeping an archived source
  # around forever.
  retry_on CalendarHub::PurgeService::RemoteCleanupError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.error("[PurgeCalendarSourceJob] #{error.message}; purging rows anyway")
    job.send(:purge, job.arguments.first, remote_cleanup: false)
  end

  def perform(source_id)
    purge(source_id, remote_cleanup: true)
  end

  private

  def purge(source_id, remote_cleanup:)
    with_error_tracking(context: "purge calendar_source_id=#{source_id}") do
      source = CalendarSource.unscoped.find_by(id: source_id)
      return unless source

      CalendarHub::PurgeService.new(source).call(remote_cleanup: remote_cleanup)
    end
  end
end
