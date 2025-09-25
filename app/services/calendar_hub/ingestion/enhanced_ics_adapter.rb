# frozen_string_literal: true

require "net/http"
require "uri"

module CalendarHub
  module Ingestion
    class EnhancedICSAdapter < GenericIcsAdapter
      def fetch_events_with_change_detection
        uri = URI(source.ingestion_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Get.new(uri.request_uri)

        if source.ics_feed_etag.present?
          request["If-None-Match"] = source.ics_feed_etag
        end

        if source.ics_feed_last_modified.present?
          request["If-Modified-Since"] = source.ics_feed_last_modified
        end

        response = http.request(request)

        case response.code.to_i
        when 304
          { changed: false, events: [] }
        when 200
          source.update!(
            ics_feed_etag: response["ETag"],
            ics_feed_last_modified: response["Last-Modified"],
          )

          events = CalendarHub::ICS::Parser.new(response.body).events
          { changed: true, events: events }
        else
          raise Ingestion::Error, "HTTP #{response.code}: #{response.message}"
        end
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
