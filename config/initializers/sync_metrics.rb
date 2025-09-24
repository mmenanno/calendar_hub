# frozen_string_literal: true

# Capture minimal sync metrics for the Admin Jobs page without extra storage.
ActiveSupport::Notifications.subscribe("calendar_hub.sync") do |_name, _start, _finish, _id, payload|
  entry = payload.merge(at: Time.current)
  key = "calendar_hub:last_sync_metrics"
  metrics = Rails.cache.read(key) || []
  metrics << entry
  metrics = metrics.last(20)
  Rails.cache.write(key, metrics)
end
