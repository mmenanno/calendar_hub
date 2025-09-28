# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  include SyncAttemptManageable

  retry_on CalendarHub::Ingestion::Error, wait: :exponentially_longer, attempts: 5

  def perform(calendar_source_id, **options)
    source = CalendarSource.find(calendar_source_id)
    sync_options = build_sync_options(options)
    attempt = nil

    with_error_tracking(context: "sync calendar_source_id=#{calendar_source_id}") do
      source.with_lock do
        attempt = find_or_create_sync_attempt(source, sync_options[:attempt_id])
        execute_sync(source, attempt, sync_options)
        attempt.finish(status: :success)
      end
    end
  rescue => e
    attempt&.finish(status: :failed, message: e.message)
    raise
  end

  private

  def build_sync_options(options)
    {
      attempt_id: options[:attempt_id],
      use_enhanced_sync: options.fetch(:use_enhanced_sync, true),
    }
  end

  def execute_sync(source, attempt, options)
    service_class = options[:use_enhanced_sync] ? CalendarHub::Sync::EnhancedSyncService : CalendarHub::Sync::SyncService
    service = service_class.new(source: source, observer: attempt)
    service.call
  end
end
