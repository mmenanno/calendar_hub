# frozen_string_literal: true

module CalendarHub
  module Shared
    class FilterAppleEventSyncer < AppleEventSyncer
      def delete_event(event, calendar_identifier: nil)
        apple_client.delete_event(
          calendar_identifier: calendar_identifier || source.calendar_identifier,
          uid: filter_uid_for(event),
        )
      end

      def sync_event(event, observer: nil)
        destination = resolve_destination(event)
        cleanup_old_destination(event, destination)

        result = if event.sync_exempt? || event.cancelled?
          delete_event(event, calendar_identifier: destination)
          observer&.delete_success(event)
          :deleted
        else
          upsert_event(event, calendar_identifier: destination)
          observer&.upsert_success(event)
          :upserted
        end
        event.update_columns(synced_at: Time.current, last_synced_to_calendar: destination)
        result
      rescue StandardError => error
        observer&.upsert_error(event, error)
        # Let FilterSyncService handle the error logging and re-raising
        raise
      end

      private

      # FilterSyncService uses a different UID format for backward compatibility
      def build_payload(event)
        payload = translator.call(event)
        payload[:uid] = filter_uid_for(event)
        payload[:summary] = ::CalendarHub::NameMapper.apply(payload[:summary], source: source)
        payload[:url] = event_url_for(event)
        payload[:x_props] = {
          "X-CH-SOURCE" => source.name,
          "X-CH-SOURCE-ID" => source.id.to_s,
        }
        payload
      end

      def filter_uid_for(event)
        "#{event.external_id}@#{source.id}.calendar-hub.local"
      end
    end
  end
end
