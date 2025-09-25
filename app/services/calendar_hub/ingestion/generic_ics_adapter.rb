# frozen_string_literal: true

require "faraday"
require "faraday/middleware"

module CalendarHub
  module Ingestion
    class GenericICSAdapter
      attr_reader :source

      def initialize(source)
        @source = source
      end
      USER_AGENT = "CalendarHub/1.0"

      def fetch_events
        raise Error, "ingestion URL is missing" if source.ingestion_url.blank?

        body = fetch_ics_body
        return [] if body.nil? # Not modified

        parser = CalendarHub::ICS::Parser.new(body, default_time_zone: source.time_zone)
        events = parser.events.map { |event| to_fetched_event(event) }

        # Filter out events that start before the import_start_date
        if source.import_start_date.present?
          events = events.select { |event| event.starts_at >= source.import_start_date }
        end

        events
      rescue Faraday::Error => error
        raise Error, error.message
      end

      private

      def fetch_ics_body
        etag = source.settings["etag"]
        last_modified = source.settings["last_modified"]
        response = http_client.get(source.ingestion_url) do |req|
          req.headers["If-None-Match"] = etag if etag.present?
          req.headers["If-Modified-Since"] = last_modified if last_modified.present?
        end

        case response.status
        when 200
          source.settings["etag"] = response.headers["etag"] if response.headers["etag"].present?
          source.settings["last_modified"] = response.headers["last-modified"] if response.headers["last-modified"].present?
          source.save! if source.settings_changed?
          response.body
        when 304
          nil
        else
          raise Error, "Unexpected response status: #{response.status}"
        end
      end

      def to_fetched_event(event)
        CalendarHub::ICS::Event.new(
          uid: event.uid,
          summary: event.summary.presence || "(untitled event)",
          description: event.description,
          location: event.location,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          status: normalized_status(event.status),
          time_zone: source.time_zone,
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

      def http_client
        @http_client ||= Faraday.new do |connection|
          connection.headers["User-Agent"] = USER_AGENT
          apply_authentication(connection)
          connection.response(:raise_error)
          connection.adapter(Faraday.default_adapter)
        end
      end

      def apply_authentication(connection)
        credentials = (source.credentials || {}).with_indifferent_access
        username = credentials[:http_basic_username]
        password = credentials[:http_basic_password]
        return if username.blank? || password.blank?

        connection.request(:authorization, :basic, username, password)
      end
    end
  end
end
