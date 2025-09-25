# frozen_string_literal: true

module CalendarHub
  class EnhancedSyncService < CalendarHub::SyncService
    def initialize(source:, apple_client: AppleCalendar::Client.new, observer: nil, adapter: nil)
      enhanced_adapter = adapter || CalendarHub::Ingestion::EnhancedICSAdapter.new(source)
      super(source: source, apple_client: apple_client, observer: observer, adapter: enhanced_adapter)
    end

    def call
      raise Ingestion::Error, "No ingestion adapter configured" if adapter.nil?
      raise ArgumentError, "Calendar identifier is required" if source.calendar_identifier.blank?

      # Check for changes before doing expensive operations
      unless adapter.respond_to?(:has_changes?) && adapter.has_changes?
        Rails.logger.info("[CalendarSync] No changes detected for source=#{source.id}, skipping sync")
        observer&.finish(status: :success)
        return []
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Fetch events with change detection
      if adapter.respond_to?(:fetch_events_with_change_detection)
        result = adapter.fetch_events_with_change_detection
        return [] unless result[:changed]

        fetched_events = result[:events]
      else
        fetched_events = adapter.fetch_events
      end

      observer.start(total: fetched_events.size)
      processed_events = upsert_events(fetched_events)
      apply_counts = push_updates_to_apple(processed_events)
      cancel_counts = cancel_missing_events(fetched_events)
      source.mark_synced!(token: generate_sync_token, timestamp: Time.current)
      observer.finish(status: :success)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      ActiveSupport::Notifications.instrument(
        "calendar_hub.sync",
        source_id: source.id,
        fetched: fetched_events.size,
        upserts: apply_counts[:upserts],
        deletes: apply_counts[:deletes] + cancel_counts[:canceled],
        canceled: cancel_counts[:canceled],
        duration_ms: duration_ms,
      )
      Rails.logger.info(
        "[CalendarSync] source=#{source.id} fetched=#{fetched_events.size} upserts=#{apply_counts[:upserts]} " \
          "deletes=#{apply_counts[:deletes] + cancel_counts[:canceled]} canceled=#{cancel_counts[:canceled]} duration_ms=#{duration_ms}",
      )
      processed_events
    end
  end
end
