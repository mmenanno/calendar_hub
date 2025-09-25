# frozen_string_literal: true

class SyncAttempt < ApplicationRecord
  include Turbo::Broadcastable

  STATUSES = {
    queued: "queued",
    running: "running",
    success: "success",
    failed: "failed",
  }.freeze

  belongs_to :calendar_source
  has_many :sync_event_results, dependent: :destroy

  enum :status, STATUSES

  after_commit :broadcast_snapshot

  def start(total: 0)
    update!(status: :running, total_events: total, started_at: Time.current)
  end

  def upsert_success(event)
    update!(upserts: upserts.to_i + 1)
    record_event(event: event, action: "upsert", success: true)
  end

  def upsert_error(event, error)
    update!(errors_count: errors_count.to_i + 1)
    record_event(event: event, action: "upsert", success: false, error_message: error.message)
  end

  def delete_success(event)
    update!(deletes: deletes.to_i + 1)
    record_event(event: event, action: "delete", success: true)
  end

  def delete_error(event, error)
    update!(errors_count: errors_count.to_i + 1)
    record_event(event: event, action: "delete", success: false, error_message: error.message)
  end

  def finish(status: :success, message: nil)
    update!(status: status, finished_at: Time.current, message: message)
  end

  def stream_name
    "sync_attempts_source_#{calendar_source_id}"
  end

  private

  def record_event(event:, action:, success:, error_message: nil)
    sync_event_results.create!(
      calendar_event: event.is_a?(CalendarEvent) ? event : nil,
      external_id: event.respond_to?(:external_id) ? event.external_id : event.to_s,
      action: action,
      success: success,
      error_message: error_message,
      occurred_at: Time.current,
    )
  rescue => e
    Rails.logger.warn("[SyncAttempt] Failed to record event result: #{e.message}")
  end

  def broadcast_snapshot
    broadcast_replace_to(
      stream_name,
      target: "sync_status_source_#{calendar_source_id}",
      partial: "calendar_sources/sync_status",
      locals: { attempt: self },
    )
  end
end
