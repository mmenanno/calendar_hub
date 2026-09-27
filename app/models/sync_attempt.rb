# frozen_string_literal: true

# A sync run for one source. Also acts as the sync observer: per-event
# progress is counted in memory and flushed in batches (every
# FLUSH_EVERY_EVENTS events or FLUSH_INTERVAL) with a single UPDATE and a
# throttled, asynchronous status broadcast. Only failures are stored as
# SyncEventResult rows.
class SyncAttempt < ApplicationRecord
  include Turbo::Broadcastable

  STATUSES = {
    queued: "queued",
    running: "running",
    success: "success",
    failed: "failed",
  }.freeze

  FLUSH_EVERY_EVENTS = 100
  FLUSH_INTERVAL = 2.seconds
  STALE_AFTER = 2.hours

  belongs_to :calendar_source
  has_many :sync_event_results, dependent: :destroy

  enum :status, STATUSES

  after_commit :broadcast_snapshot

  # Stale attempts are queued/running ones without progress for too long.
  # updated_at acts as a heartbeat: every progress flush touches it, so a
  # long-running sync is not mistaken for a dead one.
  scope :stale, lambda { |threshold: STALE_AFTER|
    where(status: ["queued", "running"])
      .where(updated_at: ...(Time.current - threshold))
  }

  def start(total: 0)
    reset_pending_progress
    update!(status: :running, total_events: total, started_at: Time.current)
  end

  def upsert_success(_event)
    record_progress(:upserts)
  end

  def upsert_error(event, error)
    record_failure(event, "upsert", error)
  end

  def delete_success(_event)
    record_progress(:deletes)
  end

  def delete_error(event, error)
    record_failure(event, "delete", error)
  end

  def finish(status: :success, message: nil)
    flush_progress!(broadcast: false)
    update!(status: status, finished_at: Time.current, message: message)
  end

  # Records a note while keeping the attempt active (e.g. "will retry"); also
  # refreshes the heartbeat.
  def note!(message)
    update!(message: message)
  end

  # Writes buffered counters and failure rows.
  def flush_progress!(broadcast: true)
    return if pending_count.zero? && pending_failures.empty?

    now = Time.current
    self.upserts = upserts.to_i + pending_counts[:upserts]
    self.deletes = deletes.to_i + pending_counts[:deletes]
    self.errors_count = errors_count.to_i + pending_counts[:errors_count]
    update_columns(upserts: upserts, deletes: deletes, errors_count: errors_count, updated_at: now) # rubocop:disable Rails/SkipsModelValidations -- batched progress flush on the sync hot path
    insert_failures(now)
    reset_pending_progress
    @last_flush_at = monotonic_now
    broadcast_progress if broadcast
  end

  def stale?(threshold: STALE_AFTER)
    (queued? || running?) && updated_at < Time.current - threshold
  end

  def stream_name
    "sync_attempts_source_#{calendar_source_id}"
  end

  private

  def pending_counts
    @pending_counts ||= { upserts: 0, deletes: 0, errors_count: 0 }
  end

  def pending_failures
    @pending_failures ||= []
  end

  def pending_count
    pending_counts.values.sum
  end

  def reset_pending_progress
    @pending_counts = { upserts: 0, deletes: 0, errors_count: 0 }
    @pending_failures = []
  end

  def record_progress(counter)
    pending_counts[counter] += 1
    flush_progress! if flush_due?
  end

  def record_failure(event, action, error)
    pending_failures << {
      calendar_event_id: event.is_a?(CalendarEvent) && event.persisted? ? event.id : nil,
      external_id: event.respond_to?(:external_id) ? event.external_id.to_s : event.to_s,
      action: action,
      success: false,
      error_message: error.message.to_s.truncate(1_000),
    }
    record_progress(:errors_count)
  end

  def flush_due?
    pending_count >= FLUSH_EVERY_EVENTS || monotonic_now - (@last_flush_at ||= monotonic_now) >= FLUSH_INTERVAL
  end

  def insert_failures(now)
    return if pending_failures.empty?

    rows = pending_failures.map do |row|
      row.merge(sync_attempt_id: id, occurred_at: now, created_at: now, updated_at: now)
    end
    SyncEventResult.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations -- batched progress flush on the sync hot path
  rescue ActiveRecord::ActiveRecordError => exception
    Rails.logger.warn("[SyncAttempt] Failed to record event results: #{exception.message}")
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def broadcast_progress
    broadcast_replace_later_to(
      stream_name,
      target: "sync_status_source_#{calendar_source_id}",
      partial: "calendar_sources/sync_status",
      locals: { attempt: self },
    )
  rescue StandardError => exception
    Rails.logger.warn("[SyncAttempt] Failed to broadcast progress: #{exception.message}")
  end

  def broadcast_snapshot
    broadcast_replace_to(
      stream_name,
      target: "sync_status_source_#{calendar_source_id}",
      partial: "calendar_sources/sync_status",
      locals: { attempt: self },
    )

    return if finished_at.blank?

    broadcast_replace_to(
      "calendar_sources",
      target: ActionView::RecordIdentifier.dom_id(calendar_source, :card),
      partial: "calendar_sources/source",
      locals: { source: calendar_source.reload },
    )
  end
end
