# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Shared
    class HttpClientTest < ActiveSupport::TestCase
      include EnvHelpers
      include CredentialHelpers

      setup do
        @source = calendar_sources(:ics_feed)
        @client = HttpClient.new(@source)
      end

      test "configures open_timeout on Faraday connection" do
        connection = @client.send(:build_connection)

        assert_equal(HttpClient::OPEN_TIMEOUT, connection.options.open_timeout)
      end

      test "configures read_timeout on Faraday connection" do
        connection = @client.send(:build_connection)

        assert_equal(HttpClient::READ_TIMEOUT, connection.options.timeout)
      end

      test "caps per-hop timeouts at the time left before the deadline" do
        clock = [0.0]
        client = HttpClient.new(@source, deadline: 45)
        client.define_singleton_method(:monotonic_now) { clock.first }
        client.send(:start_deadline!)
        clock[0] = 40.0

        connection = client.send(:build_connection)

        assert_in_delta(5.0, connection.options.open_timeout)
        assert_in_delta(5.0, connection.options.timeout)
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

      test "refuses to fetch without auth when the saved credentials can't be decrypted" do
        @source.update_column(:credentials, foreign_ciphertext(http_basic_username: "u", http_basic_password: "p"))
        source = CalendarSource.find(@source.id)

        error = assert_raises(CalendarHub::Ingestion::Error) { HttpClient.new(source).get_with_caching(source.ingestion_url) }

        assert_match(/can't be decrypted/, error.message)
        assert_not_requested(:get, source.ingestion_url)
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

      # --- Scheme checks --------------------------------------------------

      test "rejects non-http feed URLs" do
        ["ftp://example.com/feed.ics", "file:///etc/passwd", "gopher://example.com/", "example.com/feed.ics"].each do |url|
          assert_raises(CalendarHub::Ingestion::InvalidFeedURLError, url) { @client.get_with_caching(url) }
        end
      end

      test "refuses to follow a redirect to a non-http scheme" do
        stub_request(:get, @source.ingestion_url).to_return(status: 302, headers: { "Location" => "file:///etc/passwd" })

        assert_raises(CalendarHub::Ingestion::InvalidFeedURLError) { @client.get_with_caching(@source.ingestion_url) }
      end

      test "fetchable_url? accepts only http(s) URLs with a host" do
        assert(HttpClient.fetchable_url?("https://example.com/a.ics"))
        assert(HttpClient.fetchable_url?("HTTP://example.com/a.ics"))
        assert(HttpClient.fetchable_url?("webcal://example.com/a.ics"))
        refute(HttpClient.fetchable_url?("ftp://example.com/a.ics"))
        refute(HttpClient.fetchable_url?("https:///a.ics"))
        refute(HttpClient.fetchable_url?("http://[bad"))
        refute(HttpClient.fetchable_url?(""))
      end

      # --- Size cap and deadline --------------------------------------------

      test "streams the body and returns it" do
        body = "BEGIN:VCALENDAR\n#{"X" * 50_000}\nEND:VCALENDAR"
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: body)

        result = @client.get_with_caching(@source.ingestion_url)

        assert_equal(body, result[:body])
      end

      test "applies the charset from the Content-Type header" do
        stub_request(:get, @source.ingestion_url)
          .to_return(status: 200, body: "BEGIN:VCALENDAR\nSUMMARY:Café ☕", headers: { "Content-Type" => "text/calendar; charset=utf-8" })

        result = @client.get_with_caching(@source.ingestion_url)

        assert_equal(Encoding::UTF_8, result[:body].encoding)
        assert_equal("BEGIN:VCALENDAR\nSUMMARY:Café ☕", result[:body])
      end

      test "raises FeedTooLargeError when the body exceeds the size cap" do
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: "X" * 11)

        error = assert_raises(CalendarHub::Ingestion::FeedTooLargeError) do
          HttpClient.new(@source, max_body_bytes: 10).get_with_caching(@source.ingestion_url)
        end

        assert_match(/larger than/, error.message)
      end

      test "accepts a body exactly at the size cap" do
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: "X" * 10)

        result = HttpClient.new(@source, max_body_bytes: 10).get_with_caching(@source.ingestion_url)

        assert_equal("X" * 10, result[:body])
      end

      test "max_body_bytes defaults to 10 MB and honours CALENDAR_HUB_MAX_FEED_BYTES" do
        with_env("CALENDAR_HUB_MAX_FEED_BYTES" => nil) { assert_equal(10 * 1024 * 1024, HttpClient.max_body_bytes) }
        with_env("CALENDAR_HUB_MAX_FEED_BYTES" => "2048") { assert_equal(2048, HttpClient.max_body_bytes) }
        with_env("CALENDAR_HUB_MAX_FEED_BYTES" => "lots") { assert_equal(HttpClient::MAX_BODY_BYTES, HttpClient.max_body_bytes) }
        with_env("CALENDAR_HUB_MAX_FEED_BYTES" => "0") { assert_equal(HttpClient::MAX_BODY_BYTES, HttpClient.max_body_bytes) }
      end

      test "raises FeedDeadlineError when the body is still arriving at the deadline" do
        clock = [0.0]
        client = HttpClient.new(@source, deadline: 45)
        client.define_singleton_method(:monotonic_now) { clock.first }
        stub_request(:get, @source.ingestion_url).to_return do
          clock[0] = 46.0
          { status: 200, body: "BEGIN:VCALENDAR" }
        end

        assert_raises(CalendarHub::Ingestion::FeedDeadlineError) { client.get_with_caching(@source.ingestion_url) }
      end

      test "does not start another redirect hop after the deadline" do
        clock = [0.0]
        client = HttpClient.new(@source, deadline: 45)
        client.define_singleton_method(:monotonic_now) { clock.first }
        stub_request(:get, @source.ingestion_url).to_return do
          clock[0] = 50.0
          { status: 302, headers: { "Location" => "https://cdn.example.com/moved.ics" } }
        end
        moved = stub_request(:get, "https://cdn.example.com/moved.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")

        assert_raises(CalendarHub::Ingestion::FeedDeadlineError) { client.get_with_caching(@source.ingestion_url) }
        assert_not_requested(moved)
      end

      test "still handles 304 Not Modified with streaming" do
        @source.settings = @source.settings.merge("etag" => '"v1"')
        stub_request(:get, @source.ingestion_url).with(headers: { "If-None-Match" => '"v1"' }).to_return(status: 304, body: "")

        result = @client.get_with_caching(@source.ingestion_url)

        assert_equal({ status: :not_modified, body: nil, changed: false, cache_headers: nil }, result)
      end

      test "raises FeedHTTPError carrying the status for error responses" do
        stub_request(:get, @source.ingestion_url).to_return(status: 503, body: "down")

        error = assert_raises(CalendarHub::Ingestion::FeedHTTPError) { @client.get_with_caching(@source.ingestion_url) }

        assert_equal(503, error.status)
      end

      test "raises FeedConnectionError for timeouts and refused connections" do
        stub_request(:get, @source.ingestion_url).to_timeout

        assert_raises(CalendarHub::Ingestion::FeedConnectionError) { @client.get_with_caching(@source.ingestion_url) }
      end

      # --- Opt-in private address blocking ----------------------------------

      test "private address blocking is off by default" do
        with_env("CALENDAR_HUB_BLOCK_PRIVATE_FEEDS" => nil) { refute_predicate(HttpClient, :block_private_addresses?) }
        with_env("CALENDAR_HUB_BLOCK_PRIVATE_FEEDS" => "false") { refute_predicate(HttpClient, :block_private_addresses?) }
        with_env("CALENDAR_HUB_BLOCK_PRIVATE_FEEDS" => "true") { assert_predicate(HttpClient, :block_private_addresses?) }
        with_env("CALENDAR_HUB_BLOCK_PRIVATE_FEEDS" => "1") { assert_predicate(HttpClient, :block_private_addresses?) }
      end

      test "fetches LAN feeds when blocking is off" do
        AddressGuard.expects(:resolve).never
        stub = stub_request(:get, "http://192.168.1.20/cal.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")

        with_env("CALENDAR_HUB_BLOCK_PRIVATE_FEEDS" => nil) do
          HttpClient.new(@source).get_with_caching("http://192.168.1.20/cal.ics")
        end

        assert_requested(stub)
      end

      test "blocks hosts resolving to private addresses when enabled" do
        {
          "loopback.example" => ["127.0.0.1"],
          "rfc1918.example" => ["10.1.2.3"],
          "home.example" => ["192.168.0.10"],
          "metadata.example" => ["169.254.169.254"],
          "cgnat.example" => ["100.64.0.1"],
          "v6-loopback.example" => ["::1"],
          "v6-ula.example" => ["fd00::1"],
          "v6-link-local.example" => ["fe80::1"],
          "mapped.example" => ["::ffff:10.0.0.1"],
          "mixed.example" => ["93.184.216.34", "10.0.0.1"],
        }.each do |host, addresses|
          AddressGuard.stubs(:resolve).with(host, anything).returns(addresses)

          assert_raises(CalendarHub::Ingestion::BlockedAddressError, host) do
            HttpClient.new(@source, block_private_addresses: true).get_with_caching("https://#{host}/feed.ics")
          end
        end
        assert_not_requested(:get, /.*/)
      end

      test "blocks literal private IP hosts when enabled" do
        ["http://127.0.0.1/feed.ics", "http://169.254.169.254/latest/meta-data", "http://[::1]/feed.ics", "http://[::ffff:192.168.1.1]/feed.ics", "http://0.0.0.0/"].each do |url|
          assert_raises(CalendarHub::Ingestion::BlockedAddressError, url) do
            HttpClient.new(@source, block_private_addresses: true).get_with_caching(url)
          end
        end
      end

      test "blocks a redirect to a private address when enabled" do
        AddressGuard.stubs(:resolve).with("example.com", anything).returns(["93.184.216.34"])
        AddressGuard.stubs(:resolve).with("internal.example", anything).returns(["10.0.0.7"])
        stub_request(:get, @source.ingestion_url).to_return(status: 302, headers: { "Location" => "http://internal.example/admin" })
        internal = stub_request(:get, "http://internal.example/admin")

        assert_raises(CalendarHub::Ingestion::BlockedAddressError) do
          HttpClient.new(@source, block_private_addresses: true).get_with_caching(@source.ingestion_url)
        end
        assert_not_requested(internal)
      end

      test "pins each hop's connection to the validated address when enabled" do
        AddressGuard.stubs(:resolve).with("example.com", anything).returns(["93.184.216.34"])
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: "BEGIN:VCALENDAR")
        pinned = []
        Net::HTTP.any_instance.stubs(:ipaddr=).with { |ip| pinned << ip }

        HttpClient.new(@source, block_private_addresses: true).get_with_caching(@source.ingestion_url)

        assert_equal(["93.184.216.34"], pinned)
      end

      test "the net_http adapter applies the pinned address to Net::HTTP" do
        connection = @client.send(:build_connection, pinned_ip: "93.184.216.34")
        adapter = connection.builder.adapter.build
        http = Net::HTTP.new("example.com", 443)

        adapter.send(:configure_request, http, Faraday::RequestOptions.new)

        assert_equal("93.184.216.34", http.ipaddr)
        assert_equal("example.com", http.address)
      end

      test "does not pin connections when blocking is off" do
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: "BEGIN:VCALENDAR")
        Net::HTTP.any_instance.expects(:ipaddr=).never

        HttpClient.new(@source, block_private_addresses: false).get_with_caching(@source.ingestion_url)
      end
    end
  end
end
