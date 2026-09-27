# frozen_string_literal: true

module CalendarHub
  module Ingestion
    class GenericICSAdapter
      attr_reader :source, :http_client, :cache_headers

      def initialize(source)
        @source = source
        @http_client = ::CalendarHub::Shared::HttpClient.new(source)
      end

      # Returns the feed's events, or nil when the server answered 304 Not
      # Modified. Pass conditional: false to ignore the stored ETag /
      # Last-Modified and always download the full feed.
      #
      # The response's cache validators are exposed via #cache_headers; they
      # are only persisted by the caller once the sync succeeded.
      def fetch_events(conditional: true)
        raise Error, "ingestion URL is missing" if source.ingestion_url.blank?

        result = http_client.get_with_caching(source.ingestion_url, conditional: conditional)
        @cache_headers = result[:cache_headers]
        return unless result[:changed] # 304 Not Modified — nil signals "no change" to callers

        parser = ::CalendarHub::ICS::Parser.new(
          result[:body],
          default_time_zone: source.time_zone,
          window_start: recurrence_window_start,
        )
        raise Error, "Feed did not return an iCalendar document" unless parser.calendar?

        events = parser.events.map { |event| to_fetched_event(event) }

        # Applied to expanded occurrences (not series masters) so a series
        # that began before import_start_date still yields later occurrences.
        events = events.select { |event| event.starts_at >= source.import_start_date } if source.import_start_date.present?

        events
      end

      # Earliest start of expanded recurring occurrences. Occurrences older
      # than this are no longer produced, so the sync must not treat them as
      # removed from the feed.
      def recurrence_window_start
        @recurrence_window_start ||= [
          source.import_start_date,
          Time.current - ::CalendarHub::ICS::Parser::RECURRENCE_LOOKBACK,
        ].compact.max
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
