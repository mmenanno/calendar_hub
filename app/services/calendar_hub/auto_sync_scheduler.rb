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
      # Use a subquery to exclude sources with active sync attempts in a single
      # SQL statement, avoiding the N+1 per-source EXISTS query (BUG-015).
      active_attempt_source_ids = SyncAttempt
        .where(status: %w[queued running])
        .where("created_at >= ?", 2.hours.ago)
        .select(:calendar_source_id)

      CalendarSource.active.auto_sync_enabled
        .where.not(id: active_attempt_source_ids)
        .select { |source| source.sync_due?(now: @now) && source.within_sync_window?(now: @now) }
    end

    def schedule_syncs(sources)
      return 0 if sources.empty?

      # Build a lookup for sources by id to avoid re-fetching from DB
      sources_by_id = sources.index_by(&:id)

      # Optimize scheduling by domain to reduce connection overhead
      schedule = ::CalendarHub::DomainOptimizer.optimize_sync_schedule(sources)
      scheduled_count = 0

      schedule.each do |source_id, scheduled_at|
        source = sources_by_id[source_id] || CalendarSource.find(source_id)
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
