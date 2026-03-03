# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Shared
    class HttpClientTest < ActiveSupport::TestCase
      setup do
        @source = calendar_sources(:ics_feed)
        @client = HttpClient.new(@source)
      end

      test "configures open_timeout on Faraday connection" do
        connection = @client.send(:http_client)

        assert_equal HttpClient::OPEN_TIMEOUT, connection.options.open_timeout
      end

      test "configures read_timeout on Faraday connection" do
        connection = @client.send(:http_client)

        assert_equal HttpClient::READ_TIMEOUT, connection.options.timeout
      end

      test "raises Ingestion::Error with descriptive message on timeout" do
        stub_request(:get, @source.ingestion_url).to_timeout

        error = assert_raises(CalendarHub::Ingestion::Error) do
          @client.get_with_caching(@source.ingestion_url)
        end

        assert_match(/HTTP (connection failed|request timed out|request failed)/i, error.message)
      end

      test "raises Ingestion::Error with descriptive message on connection failure" do
        stub_request(:get, @source.ingestion_url).to_raise(Faraday::ConnectionFailed.new("Connection refused"))

        error = assert_raises(CalendarHub::Ingestion::Error) do
          @client.get_with_caching(@source.ingestion_url)
        end

        assert_match(/connection failed/i, error.message)
      end
    end
  end
end
