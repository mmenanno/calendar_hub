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

        assert_equal(HttpClient::OPEN_TIMEOUT, connection.options.open_timeout)
      end

      test "configures read_timeout on Faraday connection" do
        connection = @client.send(:http_client)

        assert_equal(HttpClient::READ_TIMEOUT, connection.options.timeout)
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

      test "follows redirects up to the limit" do
        stub_request(:get, @source.ingestion_url).to_return(status: 301, headers: { "Location" => "https://cdn.example.com/moved.ics" })
        stub_request(:get, "https://cdn.example.com/moved.ics").to_return(status: 200, body: "BEGIN:VCALENDAR", headers: { "ETag" => '"v2"' })

        result = @client.get_with_caching(@source.ingestion_url)

        assert_equal("BEGIN:VCALENDAR", result[:body])
        assert_equal({ etag: '"v2"', last_modified: nil }, result[:cache_headers])
      end

      test "raises after too many redirects" do
        stub_request(:get, %r{https://loop\.example\.com/\d+}).to_return do |request|
          next_id = request.uri.path.delete("/").to_i + 1
          { status: 302, headers: { "Location" => "https://loop.example.com/#{next_id}" } }
        end

        error = assert_raises(CalendarHub::Ingestion::Error) do
          @client.get_with_caching("https://loop.example.com/0")
        end

        assert_match(/redirected more than 5 times/, error.message)
      end

      test "does not send credentials to a different host after a redirect" do
        @source.credentials = { http_basic_username: "user", http_basic_password: "secret" }
        stub_request(:get, @source.ingestion_url).with(basic_auth: ["user", "secret"])
          .to_return(status: 302, headers: { "Location" => "https://other.example.net/feed.ics" })
        other = stub_request(:get, "https://other.example.net/feed.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")

        HttpClient.new(@source).get_with_caching(@source.ingestion_url)

        assert_requested(other)
        assert_not_requested(:get, "https://other.example.net/feed.ics", headers: { "Authorization" => /Basic/ })
      end

      test "sends basic auth over https" do
        @source.credentials = { http_basic_username: "user", http_basic_password: "secret" }
        stub = stub_request(:get, @source.ingestion_url).with(basic_auth: ["user", "secret"]).to_return(status: 200, body: "BEGIN:VCALENDAR")

        HttpClient.new(@source).get_with_caching(@source.ingestion_url)

        assert_requested(stub)
      end

      test "never sends basic auth over plain http" do
        @source.credentials = { http_basic_username: "user", http_basic_password: "secret" }
        stub = stub_request(:get, "http://example.com/feed.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")

        HttpClient.new(@source).get_with_caching("http://example.com/feed.ics")

        assert_requested(stub)
        assert_not_requested(:get, "http://example.com/feed.ics", headers: { "Authorization" => /Basic/ })
      end

      test "same_host? compares normalized hosts case-insensitively" do
        assert(HttpClient.same_host?("https://Example.com/a.ics", "webcal://example.COM/b.ics"))
        refute(HttpClient.same_host?("https://example.com/a.ics", "https://example.org/a.ics"))
        refute(HttpClient.same_host?("https://example.com/a.ics", "not a url"))
        refute(HttpClient.same_host?(nil, "https://example.com/a.ics"))
      end

      test "normalizes webcal URLs to https" do
        stub = stub_request(:get, "https://example.com/cal.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")

        @client.get_with_caching("webcal://example.com/cal.ics")

        assert_requested(stub)
      end

      test "does not leak the feed URL in error messages" do
        secret_url = "https://example.com/private-abc123/basic.ics?token=s3cret"
        stub_request(:get, secret_url).to_return(status: 404, body: "nope")

        error = assert_raises(CalendarHub::Ingestion::Error) do
          @client.get_with_caching(secret_url)
        end

        refute_includes(error.message, "s3cret")
        refute_includes(error.message, "private-abc123")
      end

      test "scrubs URLs out of connection error messages" do
        secret_url = "https://example.com/feed.ics?token=s3cret"
        stub_request(:get, secret_url).to_raise(Faraday::ConnectionFailed.new("Failed to open #{secret_url}"))

        error = assert_raises(CalendarHub::Ingestion::Error) do
          @client.get_with_caching(secret_url)
        end

        refute_includes(error.message, "s3cret")
        assert_includes(error.message, "https://example.com/…")
      end

      test "returns cache headers without saving the source" do
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: "BEGIN:VCALENDAR", headers: { "ETag" => '"abc"' })

        result = @client.get_with_caching(@source.ingestion_url)

        assert_equal('"abc"', result[:cache_headers][:etag])
        assert_nil(@source.reload.settings["etag"])
      end
    end
  end
end
