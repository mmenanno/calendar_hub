# frozen_string_literal: true

require "digest"

module CalendarHub
  module Shared
    # Pushes CalendarEvents to Apple Calendar.
    #
    # Each successful push stores a digest of the exact payload and
    # destination (CalendarEvent#synced_fingerprint). Events whose mapped
    # payload and destination are unchanged are skipped, so a sync only talks
    # to iCloud for new/changed events, mapping changes and pending deletes.
    class AppleEventSyncer
      # synced_fingerprint of an event that is known not to exist in iCloud.
      DELETED_SIGNATURE = "deleted"

      attr_reader :source, :apple_client, :translator

      def initialize(source:, apple_client: AppleCalendar::Client.new, name_mapper: nil)
        @source = source
        @apple_client = apple_client
        @translator = ::CalendarHub::Translators::EventTranslator.new(source)
        @name_mapper = name_mapper
      end

      # Mappings are loaded (and regexes compiled) once per syncer, i.e. once
      # per sync run.
      def name_mapper
        @name_mapper ||= ::CalendarHub::NameMapper.for(source)
      end

      # Returns :upserted, :deleted, :skipped or :error.
      def sync_event(event, observer: nil, force: false)
        if event.sync_exempt? || event.cancelled?
          remove_event(event, observer: observer, force: force)
        else
          push_event(event, observer: observer, force: force)
        end
      rescue StandardError => exception
        if event.sync_exempt? || event.cancelled?
          observer&.delete_error(event, exception)
        else
          observer&.upsert_error(event, exception)
        end
        Rails.logger.error("[AppleEventSyncer] Failed to sync event #{event.external_id}: #{exception.message}")
        :error
      end

      # Deletes the event from the calendar it was last pushed to (falling back
      # to the source calendar).
      def delete_event(event, calendar_identifier: nil)
        apple_client.delete_event(
          calendar_identifier: calendar_identifier || event.last_synced_to_calendar.presence || source.calendar_identifier,
          uid: ::CalendarHub::Shared::UidGenerator.composite_uid_for(event),
        )
      end

      def upsert_event(event, calendar_identifier: nil, payload: build_payload(event))
        apple_client.upsert_event(
          calendar_identifier: calendar_identifier || source.calendar_identifier,
          payload: payload,
        )
      end

      def sync_events_batch(events, observer: nil, force: false)
        counts = { upserts: 0, deletes: 0, skipped: 0, errors: 0 }

        events.sort_by(&:starts_at).each do |event|
          case sync_event(event, observer: observer, force: force)
          when :upserted then counts[:upserts] += 1
          when :deleted then counts[:deletes] += 1
          when :skipped then counts[:skipped] += 1
          when :error then counts[:errors] += 1
          end
        end

        counts
      end

      private

      def push_event(event, observer:, force:)
        destination = resolve_destination(event)
        payload = build_payload(event)
        signature = signature_for(payload, destination)
        return :skipped if !force && event.synced_fingerprint == signature && event.last_synced_to_calendar == destination

        cleanup_old_destination(event, destination)
        upsert_event(event, calendar_identifier: destination, payload: payload)
        event.update_columns(synced_at: Time.current, last_synced_to_calendar: destination, synced_fingerprint: signature)
        observer&.upsert_success(event)
        :upserted
      end

      def remove_event(event, observer:, force:)
        target = event.last_synced_to_calendar
        if target.blank? && !force
          # Never pushed (or already deleted): nothing to remove remotely.
          mark_removed(event) unless event.synced_fingerprint == DELETED_SIGNATURE
          return :skipped
        end

        delete_event(event, calendar_identifier: target.presence)
        mark_removed(event)
        observer&.delete_success(event)
        :deleted
      end

      def mark_removed(event)
        event.update_columns(synced_at: Time.current, last_synced_to_calendar: nil, synced_fingerprint: DELETED_SIGNATURE)
      end

      def resolve_destination(event)
        name_mapper.destination_for(event.title) || source.calendar_identifier
      end

      # When an event's destination calendar changes (e.g., a mapping override
      # routes it to a different calendar), delete it from the old calendar first.
      # iCloud enforces UID uniqueness across calendars, so leaving the old copy
      # causes 412 Precondition Failed on the PUT to the new calendar.
      def cleanup_old_destination(event, new_destination)
        old_destination = event.last_synced_to_calendar
        return if old_destination.blank? || old_destination == new_destination

        Rails.logger.info(
          "[AppleEventSyncer] Destination changed for #{event.external_id}: " \
          "#{old_destination} -> #{new_destination}, deleting from old calendar",
        )
        delete_event(event, calendar_identifier: old_destination)
      rescue StandardError => exception
        Rails.logger.warn(
          "[AppleEventSyncer] Failed to delete #{event.external_id} from old calendar #{old_destination}: #{exception.message}",
        )
      end

      def build_payload(event)
        payload = translator.call(event)
        payload[:summary] = name_mapper.apply(payload[:summary])
        payload[:url] = event_url_for(event)
        payload[:x_props] = {
          "X-CH-SOURCE" => source.name,
          "X-CH-SOURCE-ID" => source.id.to_s,
        }
        payload
      end

      # Digest of everything that ends up in the pushed iCalendar object plus
      # the destination calendar.
      def signature_for(payload, destination)
        normalized = payload.transform_values do |value|
          value.respond_to?(:utc) ? value.utc.iso8601 : value
        end
        Digest::SHA256.hexdigest([destination, normalized.sort_by { |key, _| key.to_s }].to_json)
      end

      def event_url_for(event)
        Rails.application.routes.url_helpers.calendar_event_url(event, **::CalendarHub::UrlOptions.for_links)
      rescue StandardError
        nil
      end
    end
  end
end
