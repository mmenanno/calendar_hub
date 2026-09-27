# frozen_string_literal: true

# Prunes history tables that otherwise grow forever (every sync writes an
# attempt, a metric, a result per event and audits for changed events), then
# lets SQLite refresh its query planner statistics.
#
# Deletes run in small batches, each in its own short transaction, so the
# write lock is never held for long while syncs are running.
class RetentionJob < ApplicationJob
  SYNC_EVENT_RESULTS_RETENTION = 14.days
  SYNC_ATTEMPTS_RETENTION = 90.days
  SYNC_METRICS_RETENTION = 90.days
  EVENT_AUDITS_RETENTION = 90.days
  # Cancelled events with no copy in iCloud have nothing left to sync.
  CANCELLED_EVENTS_RETENTION = 30.days
  BATCH_SIZE = 1_000

  def perform
    now = Time.current

    deleted = {
      sync_event_results: prune(SyncEventResult.where(created_at: ...(now - SYNC_EVENT_RESULTS_RETENTION))),
      sync_attempts: prune(prunable_sync_attempts(now - SYNC_ATTEMPTS_RETENTION)),
      sync_metrics: prune(SyncMetric.where(occurred_at: ...(now - SYNC_METRICS_RETENTION))),
      calendar_event_audits: prune(CalendarEventAudit.where(occurred_at: ...(now - EVENT_AUDITS_RETENTION))),
      calendar_events: prune(prunable_cancelled_events(now - CANCELLED_EVENTS_RETENTION)),
    }

    # Cheap (usually a no-op); runs ANALYZE on tables whose stats are stale,
    # e.g. after the deletes above.
    ActiveRecord::Base.with_connection { |connection| connection.execute("PRAGMA optimize") }

    Rails.logger.info("[RetentionJob] Deleted #{deleted.map { |table, count| "#{table}=#{count}" }.join(" ")}")
    deleted
  end

  private

  # Keep each source's latest attempt (the UI shows it) and anything still
  # active. Their sync_event_results are removed by ON DELETE CASCADE.
  def prunable_sync_attempts(cutoff)
    SyncAttempt
      .where(created_at: ...cutoff)
      .where.not(status: [:queued, :running])
      .where.not(id: CalendarSource.latest_sync_attempt_ids)
  end

  # A blank last_synced_to_calendar means there's no copy in iCloud to delete
  # (never pushed, or its removal was already pushed).
  def prunable_cancelled_events(cutoff)
    CalendarEvent
      .where(status: :cancelled, last_synced_to_calendar: nil)
      .where(updated_at: ...cutoff)
  end

  # delete_all skips callbacks on purpose: no audits or Turbo broadcasts for
  # pruned rows. Dependent rows go via ON DELETE CASCADE.
  def prune(relation)
    total = 0
    relation.in_batches(of: BATCH_SIZE) { |batch| total += batch.delete_all }
    total
  end
end
