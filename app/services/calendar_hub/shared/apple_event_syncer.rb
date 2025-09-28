# frozen_string_literal: true

module CalendarHub
  module Shared
    class AppleEventSyncer
      attr_reader :source, :apple_client, :translator

      def initialize(source:, apple_client: AppleCalendar::Client.new)
        @source = source
        @apple_client = apple_client
        @translator = ::CalendarHub::Translators::EventTranslator.new(source)
      end

      def sync_event(event, observer: nil)
        if event.sync_exempt? || event.cancelled?
          delete_event(event)
          observer&.delete_success(event)
          :deleted
        else
          upsert_event(event)
          observer&.upsert_success(event)
          :upserted
        end
        event.mark_synced!
      rescue StandardError => error
        observer&.upsert_error(event, error)
        Rails.logger.error("[AppleEventSyncer] Failed to sync event #{event.external_id}: #{error.message}")
        :error
      end

      def delete_event(event)
        apple_client.delete_event(
          calendar_identifier: source.calendar_identifier,
          uid: ::CalendarHub::Shared::UidGenerator.composite_uid_for(event),
        )
      end

      def upsert_event(event)
        payload = build_payload(event)
        apple_client.upsert_event(
          calendar_identifier: source.calendar_identifier,
          payload: payload,
        )
      end

      def sync_events_batch(events, observer: nil)
        upserts = 0
        deletes = 0

        events.sort_by { |e| e.starts_at.to_date }.chunk { |e| e.starts_at.to_date }.each do |_date, day_events|
          day_events.each do |event|
            result = sync_event(event, observer: observer)
            case result
            when :upserted
              upserts += 1
            when :deleted
              deletes += 1
            when :error
              # Error was already logged and observer notified, continue processing
            end
          end
          # Small pause between day-batches to avoid server throttling
          sleep(0.05)
        end

        { upserts: upserts, deletes: deletes }
      end

      private

      def build_payload(event)
        payload = translator.call(event)
        payload[:summary] = ::CalendarHub::NameMapper.apply(payload[:summary], source: source)
        payload[:url] = event_url_for(event)
        payload[:x_props] = {
          "X-CH-SOURCE" => source.name,
          "X-CH-SOURCE-ID" => source.id.to_s,
        }
        payload
      end

      def event_url_for(event)
        Rails.application.routes.url_helpers.calendar_event_url(event, **::CalendarHub::UrlOptions.for_links)
      rescue
        nil
      end
    end
  end
end
