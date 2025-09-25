# frozen_string_literal: true

class AutoSyncSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    scheduled_count = 0

    # Find sources that need syncing
    due_sources = CalendarSource.active.auto_sync_enabled
      .select { |source| source.sync_due?(now: now) && source.within_sync_window?(now: now) }
      .reject { |source| source.sync_attempts.exists?(status: ["queued", "running"]) }

    return 0 if due_sources.empty?

    # Optimize scheduling by domain to reduce connection overhead
    schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(due_sources)

    schedule.each do |source_id, scheduled_at|
      source = CalendarSource.find(source_id)
      attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

      if scheduled_at <= now
        SyncCalendarJob.perform_later(source.id, attempt_id: attempt.id)
      else
        SyncCalendarJob.set(wait_until: scheduled_at).perform_later(source.id, attempt_id: attempt.id)
      end

      scheduled_count += 1
    end

    Rails.logger.info("[AutoSyncScheduler] Scheduled #{scheduled_count} sync jobs with domain optimization")
    scheduled_count
  end
end
