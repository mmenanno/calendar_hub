# frozen_string_literal: true

# Add indexes that match how events, sync attempts and sync results are
# queried, and drop indexes that are unused or a prefix of another index (they
# only cost writes -- every sync touches these tables for every event).
class TuneIndexesForFrequentQueries < ActiveRecord::Migration[8.1]
  def change
    # --- calendar_events ---------------------------------------------------
    # Events page (sync_exempt = false AND starts_at range ORDER BY starts_at)
    # and EventFilter's sync_exempt scans. Replaces (starts_at, sync_exempt),
    # which can only range-scan starts_at and filter sync_exempt row by row.
    add_index(:calendar_events, [:sync_exempt, :starts_at], name: "idx_events_sync_exempt_starts")
    remove_index(:calendar_events, [:starts_at, :sync_exempt], name: "index_calendar_events_on_starts_at_and_sync_exempt")
    # Prefix of (sync_exempt, starts_at).
    remove_index(:calendar_events, :sync_exempt, name: "index_calendar_events_on_sync_exempt")
    # Prefix of (calendar_source_id, external_id) and three other composites.
    remove_index(:calendar_events, :calendar_source_id, name: "index_calendar_events_on_calendar_source_id")
    # Never filtered on alone; source-scoped status lookups use
    # index_calendar_events_on_source_and_status.
    remove_index(:calendar_events, :all_day, name: "index_calendar_events_on_all_day")
    remove_index(:calendar_events, :status, name: "index_calendar_events_on_status")

    # --- sync_attempts -----------------------------------------------------
    # Latest attempt per source and the source page's attempt history.
    add_index(:sync_attempts, [:calendar_source_id, :created_at], name: "idx_sync_attempts_source_created")
    # Admin jobs page (recent attempts, last-24h counts) and retention.
    add_index(:sync_attempts, :created_at)
    # SyncAttempt.stale / CleanupStaleSyncAttemptsJob (status IN (...) AND
    # created_at < ?). Without it the planner range-scans created_at, which
    # matches nearly every row.
    add_index(:sync_attempts, [:status, :created_at])
    # Prefix of the composites above (idx_unique_active_sync_attempt_per_source
    # is partial, so it can't serve unfiltered lookups).
    remove_index(:sync_attempts, :calendar_source_id, name: "index_sync_attempts_on_calendar_source_id")

    # --- sync_event_results ------------------------------------------------
    # Sync status card: attempt.sync_event_results.failures.order(created_at: :desc)
    add_index(:sync_event_results, [:sync_attempt_id, :success, :created_at], name: "idx_sync_results_attempt_success_created")
    remove_index(:sync_event_results, :sync_attempt_id, name: "index_sync_event_results_on_sync_attempt_id")
    # Nothing looks results up by external_id.
    remove_index(:sync_event_results, [:sync_attempt_id, :external_id], name: "index_sync_event_results_on_sync_attempt_id_and_external_id")

    # --- prefixes of existing (calendar_event_id|calendar_source_id, occurred_at)
    remove_index(:calendar_event_audits, :calendar_event_id, name: "index_calendar_event_audits_on_calendar_event_id")
    remove_index(:sync_metrics, :calendar_source_id, name: "index_sync_metrics_on_calendar_source_id")
  end
end
