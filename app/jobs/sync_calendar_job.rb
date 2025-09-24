# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  queue_as :default

  retry_on CalendarHub::Ingestion::Error, wait: :exponentially_longer, attempts: 5

  def perform(calendar_source_id, attempt_id: nil)
    source = CalendarSource.find(calendar_source_id)
    attempt = nil
    source.with_lock do
      attempt = attempt_id ? SyncAttempt.find_by(id: attempt_id) : nil
      attempt ||= SyncAttempt.create!(calendar_source: source, status: :queued)
      service = CalendarHub::SyncService.new(source: source, observer: attempt)
      service.call
      attempt.finish(status: :success)
    end
  rescue => e
    attempt&.finish(status: :failed, message: e.message)
    raise
  end
end
