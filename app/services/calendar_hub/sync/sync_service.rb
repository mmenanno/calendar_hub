# frozen_string_literal: true

require "securerandom"

module CalendarHub
  module Sync
    class SyncService
      attr_reader :source, :adapter, :observer, :apple_syncer

      def initialize(source:, apple_client: AppleCalendar::Client.new, observer: nil, adapter: nil)
        @source = source
        @adapter = adapter || ::CalendarHub::Ingestion::GenericICSAdapter.new(source)
        @observer = observer || ::CalendarHub::Shared::NullObserver.new
        @apple_syncer = ::CalendarHub::Shared::AppleEventSyncer.new(source: source, apple_client: apple_client)
      end

      def call
        raise Ingestion::Error, "No ingestion adapter configured" if adapter.nil?
        raise ArgumentError, "Calendar identifier is required" if source.calendar_identifier.blank?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        fetched_events = adapter.fetch_events

        # nil means "no change" (e.g. HTTP 304) — skip sync entirely to avoid
        # cancel_missing_events interpreting an empty list as "all events removed".
        if fetched_events.nil?
          Rails.logger.info("[CalendarSync] No changes detected for source=#{source.id}, skipping sync")
          source.mark_synced!(token: source.sync_token || generate_sync_token, timestamp: Time.current)
          observer.finish(status: :success)
          return []
        end

        observer.start(total: fetched_events.size)

        # Suppress per-event Turbo broadcasts during bulk sync; a single
        # source-level refresh is broadcast after the sync completes.
        processed_events = nil
        apply_counts = nil
        cancel_counts = nil
        CalendarEvent.suppress_broadcasts do
          processed_events = upsert_events(fetched_events)
          apply_counts = apple_syncer.sync_events_batch(processed_events, observer: observer)
          cancel_counts = cancel_missing_events(fetched_events)
        end
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

      private

      def initialize_adapter; end

      # Wraps all event saves in a single transaction to ensure atomicity.
      # If any individual save fails, the entire batch is rolled back so the
      # database remains consistent with the prior sync state.
      def upsert_events(fetched_events)
        source_tz = source.time_zone
        events = ActiveRecord::Base.transaction do
          fetched_events.map do |fetched|
            event = source.calendar_events.find_or_initialize_by(external_id: fetched.uid)
            event.assign_attributes(
              title: fetched.summary,
              description: fetched.description,
              location: fetched.location,
              starts_at: fetched.starts_at,
              ends_at: fetched.ends_at,
              status: fetched.status,
              all_day: fetched.all_day || false,
              source_updated_at: Time.current,
              data: (event.data || {}).merge(fetched.raw_properties || {}),
            )
            event.time_zone = source_tz
            event.save!
            event
          end
        end

        ::CalendarHub::EventFilter.apply_filters(events)
        events
      end

      def cancel_missing_events(fetched_events)
        canceled = 0
        external_ids = fetched_events.map(&:uid)
        missing_events = source.calendar_events.where.not(external_id: external_ids)
        missing_events.find_each do |event|
          next if event.cancelled?

          now = Time.current
          # Consolidate status change and sync timestamp into a single UPDATE
          event.update!(status: :cancelled, source_updated_at: now, synced_at: now)
          apple_syncer.delete_event(event)
          observer.delete_success(event)
          canceled += 1
        rescue StandardError => error
          Rails.logger.warn("[CalendarSync] Failed to cancel event #{event.external_id}: #{error.message}")
          observer.delete_error(event, error)
        end
        { canceled: canceled }
      end

      def generate_sync_token
        SecureRandom.hex(16)
      end

      # Delegate methods for backward compatibility with tests
      def composite_uid_for(event)
        ::CalendarHub::Shared::UidGenerator.composite_uid_for(event)
      end

      def event_url_for(event)
        apple_syncer.send(:event_url_for, event)
      end
    end
  end
end
