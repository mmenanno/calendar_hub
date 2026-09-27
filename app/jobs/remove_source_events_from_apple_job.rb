# frozen_string_literal: true

# Removes an archived source's events from Apple Calendar. Partial failures
# are retried; missing Apple credentials are logged and skipped.
class RemoveSourceEventsFromAppleJob < ApplicationJob
  class IncompleteCleanup < StandardError
  end

  queue_as :sync

  retry_on IncompleteCleanup, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.error("[RemoveSourceEventsFromAppleJob] Giving up for source=#{job.arguments.first}: #{error.message}")
  end

  def perform(calendar_source_id)
    source = CalendarSource.unscoped.find_by(id: calendar_source_id)
    # Nothing to do if it was purged meanwhile or un-archived again.
    return if source.nil? || source.deleted_at.nil?

    result = CalendarHub::Sync::RemoteCleanupService.new(source: source).call
    raise IncompleteCleanup, "#{result.failed} events could not be deleted from iCloud" if result.failed.positive?
  end
end
