# frozen_string_literal: true

require "test_helper"

class RetentionJobTest < ActiveJob::TestCase
  setup do
    @source = calendar_sources(:provider)
    @event = calendar_events(:provider_consult)
  end

  test "deletes sync event results older than the retention period" do
    attempt = SyncAttempt.create!(calendar_source: @source, status: :success)
    old = create_result(attempt, created_at: (RetentionJob::SYNC_EVENT_RESULTS_RETENTION + 1.day).ago)
    recent = create_result(attempt, created_at: (RetentionJob::SYNC_EVENT_RESULTS_RETENTION - 1.day).ago)

    RetentionJob.perform_now

    refute(SyncEventResult.exists?(old.id))
    assert(SyncEventResult.exists?(recent.id))
  end

  test "deletes old sync attempts but keeps each source's latest and active ones" do
    SyncAttempt.where(calendar_source: @source).delete_all
    old_age = (RetentionJob::SYNC_ATTEMPTS_RETENTION + 1.day).ago
    old = SyncAttempt.create!(calendar_source: @source, status: :success, created_at: old_age - 1.day)
    old_result = create_result(old, created_at: old_age)
    stuck = SyncAttempt.create!(calendar_source: @source, status: :running, created_at: old_age)
    latest = SyncAttempt.create!(calendar_source: @source, status: :failed, created_at: old_age + 1.hour)

    RetentionJob.perform_now

    refute(SyncAttempt.exists?(old.id))
    refute(SyncEventResult.exists?(old_result.id))
    assert(SyncAttempt.exists?(stuck.id))
    assert(SyncAttempt.exists?(latest.id))
  end

  test "deletes old sync metrics and audits" do
    old_metric = SyncMetric.create!(calendar_source: @source, occurred_at: (RetentionJob::SYNC_METRICS_RETENTION + 1.day).ago)
    recent_metric = SyncMetric.create!(calendar_source: @source, occurred_at: 1.day.ago)
    old_audit = CalendarEventAudit.create!(calendar_event: @event, action: :updated, occurred_at: (RetentionJob::EVENT_AUDITS_RETENTION + 1.day).ago)
    recent_audit = CalendarEventAudit.create!(calendar_event: @event, action: :updated, occurred_at: 1.day.ago)

    RetentionJob.perform_now

    refute(SyncMetric.exists?(old_metric.id))
    assert(SyncMetric.exists?(recent_metric.id))
    refute(CalendarEventAudit.exists?(old_audit.id))
    assert(CalendarEventAudit.exists?(recent_audit.id))
  end

  test "deletes stale cancelled events that have no iCloud copy" do
    stale = Time.current - RetentionJob::CANCELLED_EVENTS_RETENTION - 1.day
    prunable = create_event("prunable", status: :cancelled, updated_at: stale)
    audit = CalendarEventAudit.create!(calendar_event: prunable, action: :updated, occurred_at: Time.current)
    in_icloud = create_event("in-icloud", status: :cancelled, updated_at: stale, last_synced_to_calendar: "personal")
    recently_cancelled = create_event("recent", status: :cancelled, updated_at: 1.day.ago)
    confirmed = create_event("confirmed", status: :confirmed, updated_at: stale)

    RetentionJob.perform_now

    refute(CalendarEvent.exists?(prunable.id))
    refute(CalendarEventAudit.exists?(audit.id))
    assert(CalendarEvent.exists?(in_icloud.id))
    assert(CalendarEvent.exists?(recently_cancelled.id))
    assert(CalendarEvent.exists?(confirmed.id))
  end

  test "returns counts per table and runs PRAGMA optimize" do
    create_result(SyncAttempt.create!(calendar_source: @source, status: :success), created_at: 1.year.ago)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }

    deleted = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { RetentionJob.perform_now }

    assert_equal(1, deleted[:sync_event_results])
    assert_equal([:sync_event_results, :sync_attempts, :sync_metrics, :calendar_event_audits, :calendar_events], deleted.keys)
    assert_includes(statements, "PRAGMA optimize")
  end

  private

  def create_result(attempt, created_at:)
    SyncEventResult.create!(sync_attempt: attempt, external_id: "uid", action: "upsert", occurred_at: created_at, created_at: created_at)
  end

  def create_event(external_id, status:, updated_at:, last_synced_to_calendar: nil)
    CalendarEvent.create!(
      calendar_source: @source,
      external_id: external_id,
      title: external_id,
      starts_at: 1.week.ago,
      ends_at: 1.week.ago + 1.hour,
      status: status,
      last_synced_to_calendar: last_synced_to_calendar,
      updated_at: updated_at,
    )
  end
end
