# frozen_string_literal: true

class SyncCalendarJob < ApplicationJob
  include SyncAttemptManageable

  retry_on CalendarHub::Ingestion::Error, wait: :exponentially_longer, attempts: 5

  # Retry on SQLite lock errors with exponential backoff
  # These can occur when multiple jobs try to write simultaneously
  retry_on ActiveRecord::StatementTimeout, wait: :exponentially_longer, attempts: 5
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3

  # Handle SQLite busy exceptions specifically
  # ActiveRecord::StatementInvalid with "database is locked" message
  retry_on ActiveRecord::StatementInvalid, wait: :exponentially_longer, attempts: 5 do |_job, exception|
    exception.message.include?("database is locked")
  end

  def perform(calendar_source_id, **options)
    source = CalendarSource.find(calendar_source_id)
    sync_options = build_sync_options(options)
    attempt = nil

    with_error_tracking(context: "sync calendar_source_id=#{calendar_source_id}") do
      # Use with_lock to prevent concurrent syncs of the same source
      # SQLite WAL mode handles this much better than rollback journal mode
      acquire_lock_and_sync(source, sync_options) do |locked_attempt|
        attempt = locked_attempt
      end
    end
  rescue ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked => e
    # These will be retried automatically, but update attempt if we have one
    attempt&.update(message: "Lock timeout, will retry: #{e.message}") if attempt && !attempt.finished_at
    raise
  rescue => e
    attempt&.finish(status: :failed, message: e.message) unless attempt&.finished_at
    raise
  end

  private

  def acquire_lock_and_sync(source, sync_options)
    source.with_lock do
      attempt = find_or_create_sync_attempt(source, sync_options[:attempt_id])
      yield(attempt) if block_given?
      execute_sync(source, attempt, sync_options)
      attempt.finish(status: :success)
      attempt
    end
  end

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
