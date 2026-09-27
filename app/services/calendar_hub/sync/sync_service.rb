# frozen_string_literal: true

require "securerandom"

module CalendarHub
  module Sync
    # Fetches a source's feed, stores its events and pushes changes to Apple
    # Calendar.
    #
    # - The feed is fetched conditionally (ETag/Last-Modified) unless this is
    #   a forced sync, the source configuration changed since the last sync,
    #   or the previous sync failed. On 304 Not Modified, pending pushes
    #   (events whose mapped payload/destination changed, failed pushes,
    #   exclusion changes, stranded deletes) are still processed.
    # - Only events whose content changed get a new source_updated_at, and
    #   only events whose pushed payload changed are sent to iCloud.
    # - Events that dropped out of the feed are deleted from iCloud first and
    #   marked cancelled only once the delete succeeded.
    # - Each event is saved on its own; a bad event is reported and skipped.
    class SyncService
      attr_reader :source, :adapter, :observer, :apple_syncer, :apple_client, :force

      def initialize(source:, apple_client: AppleCalendar::Client.new, observer: nil, adapter: nil, force: false)
        @source = source
        @apple_client = apple_client
        @adapter = adapter || ::CalendarHub::Ingestion::GenericICSAdapter.new(source)
        @observer = observer || ::CalendarHub::Shared::NullObserver.new
        @apple_syncer = ::CalendarHub::Shared::AppleEventSyncer.new(source: source, apple_client: apple_client)
        @force = force
        @counts = Hash.new(0)
      end

      def call
        raise Ingestion::Error, "No ingestion adapter configured" if adapter.nil?
        raise ArgumentError, "Calendar identifier is required" if source.calendar_identifier.blank?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @counts = Hash.new(0)
        fetched_events = adapter.fetch_events(conditional: !full_fetch?)
        processed_events = []

        # Suppress per-event Turbo broadcasts during bulk sync; a single
        # refresh is broadcast after the sync completes.
        CalendarEvent.suppress_broadcasts do
          if fetched_events.nil?
            Rails.logger.info("[CalendarSync] Feed not modified for source=#{source.id}; pushing pending changes only")
            observer.start(total: 0)
            push_events(source.calendar_events.where.not(status: "cancelled").to_a + stranded_deletes([]))
          else
            guard_against_empty_feed!(fetched_events)
            observer.start(total: fetched_events.size)
            processed_events = upsert_events(fetched_events)
            cancel_missing_events(fetched_events)
            push_events(processed_events + stranded_deletes(processed_events.map(&:id)))
          end
        end

        source.mark_synced!(
          token: generate_sync_token,
          timestamp: Time.current,
          cache_headers: fetched_events.nil? ? nil : adapter_cache_headers,
        )
        observer.finish(status: :success)
        broadcast_events_refresh
        report(fetched_events, started)
        processed_events
      ensure
        apple_client.finish if apple_client.respond_to?(:finish)
      end

      private

      def full_fetch?
        return true if force
        return true if source.consecutive_sync_failures.to_i.positive?
        return true if source.last_change_hash.blank?

        source.generate_change_hash != source.last_change_hash
      end

      # An empty feed while events exist is far more likely an outage or a
      # broken export than a genuinely empty calendar. Refuse to delete
      # everything unless the user explicitly forces the sync.
      def guard_against_empty_feed!(fetched_events)
        return if fetched_events.any? || force

        existing = source.calendar_events.where.not(status: "cancelled").count
        return if existing.zero?

        raise Ingestion::Error,
          "Feed returned no events but #{existing} events from earlier syncs exist; refusing to remove them. " \
          "If the calendar is really empty now, run Force Sync to remove them."
      end

      def upsert_events(fetched_events)
        source_tz = source.time_zone
        existing = CalendarEvent.where(calendar_source_id: source.id).index_by(&:external_id)
        filter = ::CalendarHub::EventFilter.new(source)
        now = Time.current

        unique_by_external_id(fetched_events).filter_map do |external_id, fetched|
          # calendar_source_id (not the association) so an unsaved, invalid
          # record never lands in source.calendar_events and gets autosaved.
          event = existing[external_id] || CalendarEvent.new(calendar_source_id: source.id, external_id: external_id)
          event.assign_attributes(
            title: fetched.summary,
            description: fetched.description,
            location: fetched.location,
            starts_at: fetched.starts_at,
            ends_at: fetched.ends_at,
            status: fetched.status,
            all_day: fetched.all_day || false,
            time_zone: source_tz,
            data: merged_data(event.data, fetched.raw_properties),
          )
          event.apply_rule_exclusion(filter.should_filter?(event))
          event.source_updated_at = now if event.new_record? || event.fingerprint != event.content_fingerprint
          event.save! if event.new_record? || event.changed?
          event
        rescue StandardError => exception
          record_error(:upsert, event || external_id, exception)
          nil
        end
      end

      # Last occurrence of a UID wins, matching the previous behaviour.
      def unique_by_external_id(fetched_events)
        fetched_events.index_by do |fetched|
          CalendarEvent.sanitize_external_id(fetched.uid)
        end
      end

      def merged_data(existing, raw_properties)
        kept = (existing || {}).to_h.stringify_keys.reject do |key, _value|
          CalendarEvent::IGNORED_DATA_KEYS.include?(key) || key.end_with?("_params", "_raw")
        end
        kept.merge((raw_properties || {}).to_h.stringify_keys)
      end

      def cancel_missing_events(fetched_events)
        fetched_ids = fetched_events.to_set { |fetched| CalendarEvent.sanitize_external_id(fetched.uid) }
        series_uids = fetched_ids.to_set { |id| ::CalendarHub::ICS::Parser.series_uid(id) }

        source.calendar_events.where.not(status: "cancelled").find_each do |event|
          next if fetched_ids.include?(event.external_id)
          next if expired_occurrence?(event, series_uids)

          cancel_event(event)
        end
      end

      # Occurrences of a series that is still in the feed but that now start
      # before the recurrence expansion window were not removed from the feed;
      # they simply are not generated any more. Leave them alone.
      def expired_occurrence?(event, series_uids)
        return false unless ::CalendarHub::ICS::Parser.occurrence?(event.external_id)
        return false unless series_uids.include?(::CalendarHub::ICS::Parser.series_uid(event.external_id))

        window_start = adapter.respond_to?(:recurrence_window_start) ? adapter.recurrence_window_start : nil
        window_start.present? && event.starts_at < window_start
      end

      # Delete from iCloud first; only mark cancelled once that succeeded so a
      # failed delete is retried by the next sync.
      def cancel_event(event)
        apple_syncer.delete_event(event) if event.last_synced_to_calendar.present?
        now = Time.current
        event.update!(
          status: :cancelled,
          source_updated_at: now,
          synced_at: now,
          last_synced_to_calendar: nil,
          synced_fingerprint: ::CalendarHub::Shared::AppleEventSyncer::DELETED_SIGNATURE,
        )
        observer.delete_success(event)
        @counts[:canceled] += 1
      rescue StandardError => exception
        record_error(:delete, event, exception)
      end

      # Cancelled events whose iCloud copy may still exist (e.g. an earlier
      # delete failed).
      def stranded_deletes(exclude_ids)
        source.calendar_events.pending_remote_delete.where.not(id: exclude_ids.compact).to_a
      end

      def push_events(events)
        result = apple_syncer.sync_events_batch(events, observer: observer, force: force)
        @counts[:upserts] += result[:upserts]
        @counts[:deletes] += result[:deletes]
        @counts[:skipped] += result[:skipped]
        @counts[:errors] += result[:errors]
      end

      def record_error(action, event, error)
        external_id = event.respond_to?(:external_id) ? event.external_id : event
        Rails.logger.warn("[CalendarSync] Failed to #{action} event #{external_id}: #{error.class}: #{error.message}")
        action == :delete ? observer.delete_error(event, error) : observer.upsert_error(event, error)
        @counts[:errors] += 1
      end

      def report(fetched_events, started)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        payload = {
          source_id: source.id,
          fetched: fetched_events&.size || 0,
          not_modified: fetched_events.nil?,
          upserts: @counts[:upserts],
          deletes: @counts[:deletes] + @counts[:canceled],
          canceled: @counts[:canceled],
          skipped: @counts[:skipped],
          errors: @counts[:errors],
          duration_ms: duration_ms,
        }
        ActiveSupport::Notifications.instrument("calendar_hub.sync", payload)
        Rails.logger.info("[CalendarSync] #{payload.map { |key, value| "#{key}=#{value}" }.join(" ")}")
      end

      def adapter_cache_headers
        adapter.respond_to?(:cache_headers) ? adapter.cache_headers : nil
      end

      # Per-event broadcasts are suppressed during sync; send one refresh so
      # open event lists pick up all changes at once.
      def broadcast_events_refresh
        Turbo::StreamsChannel.broadcast_refresh_later_to("calendar_events")
      rescue StandardError => exception
        Rails.logger.warn("[CalendarSync] Failed to broadcast events refresh: #{exception.message}")
      end

      def generate_sync_token
        SecureRandom.hex(16)
      end
    end
  end
end
