# frozen_string_literal: true

require "faraday"
require "faraday/middleware"

module CalendarHub
  module Shared
    class HttpClient
      USER_AGENT = "CalendarHub/1.0"

      attr_reader :source

      def initialize(source)
        @source = source
      end

      def get_with_caching(url)
        response = http_client.get(url) do |req|
          apply_conditional_headers(req)
        end

        case response.status
        when 200
          update_cache_headers(response)
          { status: :success, body: response.body, changed: true }
        when 304
          { status: :not_modified, body: nil, changed: false }
        else
          raise CalendarHub::Ingestion::Error, "HTTP #{response.status}: #{response.reason_phrase}"
        end
      rescue Faraday::Error => error
        raise CalendarHub::Ingestion::Error, "HTTP request failed: #{error.message}"
      end

      private

      def http_client
        @http_client ||= Faraday.new do |connection|
          connection.headers["User-Agent"] = USER_AGENT
          apply_authentication(connection)
          connection.response(:raise_error)
          connection.adapter(Faraday.default_adapter)
        end
      end

      def apply_conditional_headers(request)
        etag = source.settings["etag"] || source.ics_feed_etag
        last_modified = source.settings["last_modified"] || source.ics_feed_last_modified

        request.headers["If-None-Match"] = etag if etag.present?
        request.headers["If-Modified-Since"] = last_modified if last_modified.present?
      end

      def update_cache_headers(response)
        if response.headers["etag"].present?
          source.settings["etag"] = response.headers["etag"]
          # Also update the dedicated field if it exists
          source.ics_feed_etag = response.headers["etag"] if source.respond_to?(:ics_feed_etag=)
        end

        if response.headers["last-modified"].present?
          source.settings["last_modified"] = response.headers["last-modified"]
          # Also update the dedicated field if it exists
          source.ics_feed_last_modified = response.headers["last-modified"] if source.respond_to?(:ics_feed_last_modified=)
        end

        source.save! if source.settings_changed? || source.changed?
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
