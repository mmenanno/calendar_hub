# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  queue_as :default

  retry_on CalendarHub::Ingestion::Error, wait: :exponentially_longer, attempts: 5

  def perform(calendar_source_id, attempt_id: nil, use_enhanced_sync: true)
    source = CalendarSource.find(calendar_source_id)
    attempt = nil
    source.with_lock do
      attempt = attempt_id ? SyncAttempt.find(attempt_id) : SyncAttempt.create!(calendar_source: source, status: :queued)

      service_class = use_enhanced_sync ? CalendarHub::EnhancedSyncService : CalendarHub::SyncService
      service = service_class.new(source: source, observer: attempt)
      service.call
      attempt.finish(status: :success)
    end
  rescue => e
    attempt&.finish(status: :failed, message: e.message)
    raise
  end
end
