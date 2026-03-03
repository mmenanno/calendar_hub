# frozen_string_literal: true

# Capture minimal sync metrics for the Admin Jobs page without extra storage.
# Also persist to the sync_metrics table for 7-day trend views.
ActiveSupport::Notifications.subscribe("calendar_hub.sync") do |_name, _start, _finish, _id, payload|
  entry = payload.merge(at: Time.current)
  key = "calendar_hub:last_sync_metrics"
  metrics = Rails.cache.read(key) || []
  metrics << entry
  metrics = metrics.last(20)
  Rails.cache.write(key, metrics)

  # Persist to database for historical trend analysis
  begin
    SyncMetric.create!(
      calendar_source_id: payload[:source_id],
      occurred_at: Time.current,
      upserts_count: payload[:upserts].to_i,
      deletes_count: payload[:deletes].to_i,
      errors_count: payload.fetch(:errors, 0).to_i,
      duration_ms: payload[:duration_ms].to_i,
    )
  rescue => e
    Rails.logger.warn("[SyncMetrics] Failed to persist sync metric: #{e.message}")
  end
end
