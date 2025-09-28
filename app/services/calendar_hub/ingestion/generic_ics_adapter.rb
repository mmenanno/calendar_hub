# frozen_string_literal: true

module CalendarHub
  module Ingestion
    class GenericICSAdapter
      attr_reader :source, :http_client

      def initialize(source)
        @source = source
        @http_client = ::CalendarHub::Shared::HttpClient.new(source)
      end

      def fetch_events
        raise Error, "ingestion URL is missing" if source.ingestion_url.blank?

        result = http_client.get_with_caching(source.ingestion_url)
        return [] unless result[:changed] # Not modified

        parser = ::CalendarHub::ICS::Parser.new(result[:body], default_time_zone: source.time_zone)
        events = parser.events.map { |event| to_fetched_event(event) }

        # Filter out events that start before the import_start_date
        if source.import_start_date.present?
          events = events.select { |event| event.starts_at >= source.import_start_date }
        end

        events
      end

      private

      def to_fetched_event(event)
        ::CalendarHub::ICS::Event.new(
          uid: event.uid,
          summary: event.summary.presence || "(untitled event)",
          description: event.description,
          location: event.location,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          status: normalized_status(event.status),
          time_zone: source.time_zone,
          all_day: event.all_day || false,
          raw_properties: event.raw_properties,
        )
      end

      def normalized_status(value)
        case value&.downcase
        when "cancelled"
          "cancelled"
        when "tentative"
          "tentative"
        else
          "confirmed"
        end
      end
    end
  end
end
