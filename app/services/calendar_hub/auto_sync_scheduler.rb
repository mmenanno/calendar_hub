# frozen_string_literal: true

module CalendarHub
  class AutoSyncScheduler
    def initialize(now: Time.current)
      @now = now
    end

    def call
      sources = find_sources_due_for_sync
      schedule_syncs(sources)
    end

    def find_sources_due_for_sync
      CalendarSource.active.auto_sync_enabled
        .select { |source| source.sync_due?(now: @now) && source.within_sync_window?(now: @now) }
        .reject { |source| source.sync_attempts.exists?(status: ["queued", "running"]) }
    end

    def schedule_syncs(sources)
      return 0 if sources.empty?

      # Optimize scheduling by domain to reduce connection overhead
      schedule = CalendarHub::DomainOptimizer.optimize_sync_schedule(sources)
      scheduled_count = 0

      schedule.each do |source_id, scheduled_at|
        source = CalendarSource.find(source_id)
        attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

        if scheduled_at <= @now
          SyncCalendarJob.perform_later(source.id, attempt_id: attempt.id)
        else
          SyncCalendarJob.set(wait_until: scheduled_at).perform_later(source.id, attempt_id: attempt.id)
        end

        scheduled_count += 1
      end

      Rails.logger.info("[AutoSyncScheduler] Scheduled #{scheduled_count} sync jobs with domain optimization")
      scheduled_count
    end

    private

    attr_reader :now
  end
end
