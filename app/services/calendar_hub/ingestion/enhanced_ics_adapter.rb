# frozen_string_literal: true

module CalendarHub
  module Ingestion
    class EnhancedICSAdapter < CalendarHub::Ingestion::GenericICSAdapter
      def fetch_events_with_change_detection
        result = http_client.get_with_caching(source.ingestion_url)

        case result[:status]
        when :not_modified
          { changed: false, events: [] }
        when :success
          parser = ::CalendarHub::ICS::Parser.new(result[:body], default_time_zone: source.time_zone)
          events = parser.events.map { |event| to_fetched_event(event) }

          # Filter out events that start before the import_start_date
          if source.import_start_date.present?
            events = events.select { |event| event.starts_at >= source.import_start_date }
          end

          { changed: true, events: events }
        else
          raise Ingestion::Error, "Unexpected HTTP response status"
        end
      rescue CalendarHub::Ingestion::Error
        raise
      rescue StandardError => e
        raise Ingestion::Error, "Failed to fetch ICS feed: #{e.message}"
      end

      # Checks only local configuration state (mappings, settings).
      # Feed-level change detection (ETag/304) is handled separately by
      # fetch_events_with_change_detection in the sync service.
      def has_changes?
        source.last_change_hash.nil? || source.generate_change_hash != source.last_change_hash
      end
    end
  end
end
