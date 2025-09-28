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

      def has_changes?
        current_hash = source.generate_change_hash
        stored_hash = source.last_change_hash

        return true if stored_hash.nil?

        feed_result = fetch_events_with_change_detection
        return true if feed_result[:changed]

        current_hash != stored_hash
      end
    end
  end
end
