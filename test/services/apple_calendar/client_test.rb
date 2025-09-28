# frozen_string_literal: true

require "test_helper"

class AppleCalendarClientTest < ActiveSupport::TestCase
  include WebMockHelpers

  setup do
    @creds = {
      username: "user@example.com",
      app_specific_password: "pass-123",
      base_url: "https://caldav.example.test",
    }.freeze
    @client = AppleCalendar::Client.new(credentials: @creds)
    Rails.cache.clear
  end

  test "upsert_event performs PUT with ICS body to discovered path" do
    stub_caldav_discovery
    stub = stub_caldav_upsert(calendar: "Work", uid: "abc123", status: 201)

    payload = {
      uid: "abc123",
      title: "Checkup",
      description: "Annual exam",
      starts_at: Time.utc(2025, 1, 10, 15, 0, 0),
      ends_at: Time.utc(2025, 1, 10, 16, 0, 0),
    }

    @client.upsert_event(calendar_identifier: "Work", payload: payload)

    assert_requested(stub)
  end

  test "upsert_event retries with If-Match when 412" do
    stub_discovery

    # First PUT 412 then PUT with If-Match
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics").with(headers: { "If-None-Match" => "*" }).to_return(status: 412)
    stub_request(:head, "https://caldav.example.test/calendars/user/Work/abc123.ics").to_return(status: 200, headers: { "ETag" => '"123"' })
    stub = stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics").with(headers: { "If-Match" => '"123"' }).to_return(status: 204)

    payload = { uid: "abc123", title: "Checkup", description: "Annual", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }
    @client.upsert_event(calendar_identifier: "Work", payload: payload)

    assert_requested(stub)
  end

  test "delete_event performs DELETE to discovered path" do
    seed_cache("Work", url: "https://caldav.example.test/calendars/user/Work/")
    stub_caldav_discovery
    stub = stub_caldav_delete(calendar: "Work", uid: "abc123", status: 204)

    @client.delete_event(calendar_identifier: "Work", uid: "abc123")

    assert_requested(stub)
  end

  test "delete_event no-ops when APPLE_READONLY enabled" do
    ENV["APPLE_READONLY"] = "true"
    seed_cache("Work", url: "https://caldav.example.test/calendars/user/Work/")
    stub = stub_request(:delete, "https://caldav.example.test/calendars/user/Work/abc123.ics")
    @client.delete_event(calendar_identifier: "Work", uid: "abc123")

    assert_not_requested(stub)
  ensure
    ENV.delete("APPLE_READONLY")
  end

  test "delete_event handles 404 gracefully" do
    seed_cache("Work", url: "https://caldav.example.test/calendars/user/Work/")
    # Defensive stubs in case discovery is still attempted (should not be used)
    stub_request(:propfind, "https://caldav.example.test/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "https://caldav.example.test/principals/user/" }, body: "")
    stub_request(:propfind, "https://caldav.example.test/principals/user/").to_return(status: 207, body: "<d:multistatus xmlns:d=\"DAV:\" xmlns:cal=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:propstat><d:prop><cal:calendar-home-set><d:href>/calendars/user/</d:href></cal:calendar-home-set></d:prop></d:propstat></d:response></d:multistatus>")
    stub_request(:propfind, "https://caldav.example.test/calendars/user/").to_return(status: 207, body: "<d:multistatus xmlns:d=\"DAV:\" xmlns:cal=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:href>/calendars/user/Work/</d:href><d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat></d:response></d:multistatus>")
    stub = stub_request(:delete, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .to_return(status: 404, body: "Not Found")

    # Should not raise an exception and should return the uid
    result = @client.delete_event(calendar_identifier: "Work", uid: "abc123")

    assert_equal("abc123", result)
    assert_requested(stub)
  end

  test "upsert_event raises ArgumentError when calendar identifier is blank" do
    payload = { uid: "abc123", title: "Test" }

    assert_raises(ArgumentError, "calendar identifier required") do
      @client.upsert_event(calendar_identifier: "", payload: payload)
    end

    assert_raises(ArgumentError, "calendar identifier required") do
      @client.upsert_event(calendar_identifier: nil, payload: payload)
    end
  end

  test "upsert_event raises ArgumentError when uid is missing" do
    assert_raises(ArgumentError, "payload[:uid] required") do
      @client.upsert_event(calendar_identifier: "Work", payload: { title: "Test" })
    end
  end

  test "upsert_event raises ArgumentError when credentials are missing" do
    client = AppleCalendar::Client.new(credentials: {})
    payload = { uid: "abc123", title: "Test" }

    assert_raises(ArgumentError, "username required") do
      client.upsert_event(calendar_identifier: "Work", payload: payload)
    end

    client = AppleCalendar::Client.new(credentials: { username: "user" })
    assert_raises(ArgumentError, "app_specific_password required") do
      client.upsert_event(calendar_identifier: "Work", payload: payload)
    end
  end

  test "delete_event raises ArgumentError when calendar identifier is blank" do
    assert_raises(ArgumentError, "calendar identifier required") do
      @client.delete_event(calendar_identifier: "", uid: "abc123")
    end
  end

  test "delete_event raises ArgumentError when uid is blank" do
    assert_raises(ArgumentError, "uid required") do
      @client.delete_event(calendar_identifier: "Work", uid: "")
    end

    assert_raises(ArgumentError, "uid required") do
      @client.delete_event(calendar_identifier: "Work", uid: nil)
    end
  end

  test "delete_event raises ArgumentError when credentials are missing" do
    client = AppleCalendar::Client.new(credentials: {})

    assert_raises(ArgumentError, "username required") do
      client.delete_event(calendar_identifier: "Work", uid: "abc123")
    end

    client = AppleCalendar::Client.new(credentials: { username: "user" })
    assert_raises(ArgumentError, "app_specific_password required") do
      client.delete_event(calendar_identifier: "Work", uid: "abc123")
    end
  end

  test "default_credentials loads from AppSetting" do
    # Create app setting with credentials
    settings = AppSetting.instance
    settings.apple_username = "test@example.com"
    settings.apple_app_password = "test-password"
    settings.save!

    client = AppleCalendar::Client.new
    creds = client.credentials

    assert_equal("test@example.com", creds[:username])
    assert_equal("test-password", creds[:app_specific_password])
  ensure
    settings&.destroy
  end

  test "default_credentials returns empty hash when AppSetting fails" do
    # Stub AppSetting.first to raise an error
    AppSetting.stubs(:first).raises(StandardError, "Database error")

    client = AppleCalendar::Client.new

    assert_empty(client.credentials)
  ensure
    AppSetting.unstub(:first)
  end

  test "default_credentials returns empty hash when no credentials" do
    settings = AppSetting.instance
    settings.apple_username = nil
    settings.apple_app_password = nil
    settings.save!

    client = AppleCalendar::Client.new

    assert_empty(client.credentials)
  ensure
    settings&.destroy
  end

  test "base_url uses custom base_url from credentials" do
    client = AppleCalendar::Client.new(credentials: { base_url: "https://custom.example.com" })

    assert_equal("https://custom.example.com", client.send(:base_url))
  end

  test "base_url uses default when not specified" do
    client = AppleCalendar::Client.new(credentials: {})

    assert_equal("https://caldav.icloud.com", client.send(:base_url))
  end

  test "encoded_path encodes URL components" do
    result = @client.send(:encoded_path, "path with spaces/and@symbols")

    assert_equal("path%20with%20spaces/and%40symbols", result)
  end

  test "build_calendar_object_url handles relative collection_url" do
    url = @client.send(:build_calendar_object_url, "/calendars/user/Work/", "event123")
    expected = "https://caldav.example.test/calendars/user/Work/event123.ics"

    assert_equal(expected, url)
  end

  test "build_calendar_object_url handles absolute collection_url" do
    url = @client.send(:build_calendar_object_url, "https://example.com/cal/", "event123")
    expected = "https://example.com/cal/event123.ics"

    assert_equal(expected, url)
  end

  test "build_calendar_object_url adds trailing slash when needed" do
    url = @client.send(:build_calendar_object_url, "https://example.com/cal", "event123")
    expected = "https://example.com/cal/event123.ics"

    assert_equal(expected, url)
  end

  test "escape_ics escapes special characters" do
    result = @client.send(:escape_ics, "Text with ; comma, backslash\\ and newline\n")
    expected = "Text with \\; comma\\, backslash and newline\\n"

    assert_equal(expected, result)
  end

  test "build_ics includes all fields" do
    payload = {
      uid: "test-123",
      summary: "Test Event",
      title: "Ignored Title", # summary takes precedence
      description: "Test Description",
      location: "Test Location",
      starts_at: Time.utc(2025, 1, 1, 10, 0, 0),
      ends_at: Time.utc(2025, 1, 1, 11, 0, 0),
      url: "https://example.com",
      x_props: { "X-CUSTOM" => "custom-value" },
    }

    ics = @client.send(:build_ics, payload)

    assert_match(/UID:test-123/, ics)
    assert_match(/SUMMARY:Test Event/, ics)
    assert_match(/DESCRIPTION:Test Description/, ics)
    assert_match(/LOCATION:Test Location/, ics)
    assert_match(%r{URL:https://example.com}, ics)
    assert_match(/X-CUSTOM:custom-value/, ics)
  end

  test "build_ics handles empty optional fields" do
    payload = {
      uid: "test-123",
      starts_at: Time.utc(2025, 1, 1, 10, 0, 0),
      ends_at: Time.utc(2025, 1, 1, 11, 0, 0),
    }

    ics = @client.send(:build_ics, payload)

    assert_match(/UID:test-123/, ics)
    assert_match(/SUMMARY:/, ics) # Empty summary
    assert_match(/DESCRIPTION:/, ics) # Empty description
    assert_match(/LOCATION:/, ics) # Empty location
    refute_match(/URL:/, ics) # No URL line when empty
  end

  test "upsert_event handles 412 without ETag gracefully" do
    stub_discovery

    # First PUT 412, HEAD fails to return ETag, fallback PUT without If-Match
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics").with(headers: { "If-None-Match" => "*" }).to_return(status: 412)
    stub_request(:head, "https://caldav.example.test/calendars/user/Work/abc123.ics").to_return(status: 200, headers: {})
    stub = stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics").to_return(status: 204)

    payload = { uid: "abc123", title: "Test", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }
    @client.upsert_event(calendar_identifier: "Work", payload: payload)

    assert_requested(stub)
  end

  test "head_etag handles request failure" do
    stub_request(:head, "https://example.com/test").to_raise(StandardError.new("Network error"))

    result = @client.send(:head_etag, "https://example.com/test")

    assert_nil(result)
  end

  test "request raises error for non-2xx status codes" do
    stub_request(:get, "https://example.com/test").to_return(status: 500, body: "Internal Server Error")

    error = assert_raises(RuntimeError) do
      @client.send(:request, :get, "https://example.com/test")
    end
    assert_match(/CalDAV GET.*failed: 500/, error.message)
  end

  test "perform_with_retries handles 429 rate limiting" do
    # Test that 429 responses trigger retries with backoff
    stub_request(:get, "https://example.com/test")
      .to_return(status: 429, headers: { "Retry-After" => "1" })
      .then.to_return(status: 200)

    # Should not raise error - the retry logic is tested via integration
    result = @client.send(:request, :get, "https://example.com/test")

    assert_equal("200", result.code)
  end

  test "perform_with_retries handles network errors with retries" do
    # Test that network errors trigger retries
    stub_request(:get, "https://example.com/test")
      .to_raise(StandardError.new("Network error"))
      .then.to_return(status: 200)

    result = @client.send(:request, :get, "https://example.com/test")

    assert_equal("200", result.code)
  end

  test "perform_with_retries gives up after max retries" do
    # Test that persistent errors eventually give up
    stub_request(:get, "https://example.com/test")
      .to_raise(StandardError.new("Persistent network error"))

    assert_raises(StandardError, "Persistent network error") do
      @client.send(:request, :get, "https://example.com/test")
    end
  end

  test "parse_calendar_home_set raises error when node not found" do
    xml = "<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>"

    assert_raises(RuntimeError, "calendar-home-set not found") do
      @client.send(:parse_calendar_home_set, xml)
    end
  end

  test "parse_collections_for_displayname returns nil when calendar not found" do
    xml = <<~XML
      <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:href>/calendars/user/Other/</d:href>
          <d:propstat><d:prop><d:displayname>Other</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
        </d:response>
      </d:multistatus>
    XML

    result = @client.send(:parse_collections_for_displayname, xml, "Work", "https://example.com/calendars/user/")

    assert_nil(result)
  end

  test "find_calendar_collection raises error when calendar not found" do
    stub_request(:propfind, "https://caldav.example.test/calendars/user/")
      .to_return(status: 207, body: <<~XML)
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/calendars/user/Other/</d:href>
            <d:propstat><d:prop><d:displayname>Other</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
      XML

    assert_raises(RuntimeError, "Calendar 'NonExistent' not found") do
      @client.send(:find_calendar_collection, "https://caldav.example.test/calendars/user/", "NonExistent")
    end
  end

  test "cached_collection_url returns nil when no cache" do
    result = @client.send(:cached_collection_url, "Work")

    assert_nil(result)
  end

  test "follow_well_known returns location header when present" do
    stub_request(:propfind, "https://caldav.example.test/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "https://caldav.example.test/principals/user/" })

    result = @client.send(:follow_well_known)

    assert_equal("https://caldav.example.test/principals/user/", result)
  end

  test "follow_well_known returns original url when no location header" do
    stub_request(:propfind, "https://caldav.example.test/.well-known/caldav")
      .to_return(status: 200)

    result = @client.send(:follow_well_known)

    assert_equal("https://caldav.example.test/.well-known/caldav", result)
  end

  test "parse_collections_for_displayname skips responses with blank displayname" do
    xml = <<~XML
      <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:href>/calendars/user/BlankName/</d:href>
          <d:propstat><d:prop><d:displayname></d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
        </d:response>
        <d:response>
          <d:href>/calendars/user/Work/</d:href>
          <d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
        </d:response>
      </d:multistatus>
    XML

    result = @client.send(:parse_collections_for_displayname, xml, "Work", "https://example.com/calendars/user/")

    assert_equal("https://example.com/calendars/user/Work/", result)
  end

  test "parse_collections_for_displayname skips non-calendar collections" do
    xml = <<~XML
      <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:href>/calendars/user/NotCalendar/</d:href>
          <d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
        </d:response>
        <d:response>
          <d:href>/calendars/user/Work/</d:href>
          <d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
        </d:response>
      </d:multistatus>
    XML

    result = @client.send(:parse_collections_for_displayname, xml, "Work", "https://example.com/calendars/user/")

    assert_equal("https://example.com/calendars/user/Work/", result)
  end

  test "perform_with_retries hits retry limit for 429/503 status codes" do
    uri = URI("https://example.com/test")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTPGenericRequest.new("GET", false, true, uri.request_uri)

    # Mock to always return 429 to hit the retry limit
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    http.stubs(:request).returns(response)

    # Should hit the retry limit and raise "retry"
    assert_raises(RuntimeError, "retry") do
      @client.send(:perform_with_retries, http, req, uri)
    end
  ensure
    http.unstub(:request)
  end

  test "upsert_event handles non-412 errors in initial PUT" do
    stub_discovery

    # First PUT fails with 500 (not 412) - should hit the else clause that re-raises
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .with(headers: { "If-None-Match" => "*" })
      .to_return(status: 500, body: "Server Error")

    payload = { uid: "abc123", title: "Test", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }

    error = assert_raises(RuntimeError) do
      @client.upsert_event(calendar_identifier: "Work", payload: payload)
    end

    assert_match(/CalDAV PUT.*failed: 500/, error.message)
  end

  test "upsert_event fallback PUT without If-Match header" do
    stub_discovery

    # First PUT 412, HEAD returns no ETag, fallback PUT succeeds
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .with(headers: { "If-None-Match" => "*" })
      .to_return(status: 412)

    stub_request(:head, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .to_return(status: 200, headers: {}) # No ETag header

    # This should hit the fallback PUT without If-Match (line 32)
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .to_return(status: 204)

    payload = { uid: "abc123", title: "Test", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }

    result = @client.upsert_event(calendar_identifier: "Work", payload: payload)

    assert_equal("abc123", result)
  end

  test "upsert_event re-raises non-412 errors using mocha" do
    stub_discovery

    # Use Mocha to mock the request method to raise a non-412 error to hit line 35 (else + raise)
    @client.stubs(:request).raises(RuntimeError, "Network timeout")

    payload = { uid: "abc123", title: "Test", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }

    error = assert_raises(RuntimeError) do
      @client.upsert_event(calendar_identifier: "Work", payload: payload)
    end

    assert_equal("Network timeout", error.message)
  ensure
    @client.unstub(:request)
  end

  test "delete_event re-raises non-404 errors using mocha" do
    seed_cache("Work", url: "https://caldav.example.test/calendars/user/Work/")

    # Use Mocha to mock the request method to raise a non-404 error to hit line 57 (else + raise)
    @client.stubs(:request).raises(RuntimeError, "Server unavailable")

    error = assert_raises(RuntimeError) do
      @client.delete_event(calendar_identifier: "Work", uid: "abc123")
    end

    assert_equal("Server unavailable", error.message)
  ensure
    @client.unstub(:request)
  end

  test "discover_calendar_url returns cached result immediately using mocha" do
    # Use Mocha to mock cached_collection_url to return a value to hit line 96 (return cached)
    cached_url = "https://cached.example.com/calendars/user/TestCalendar/"
    @client.stubs(:cached_collection_url).with("TestCalendar").returns(cached_url)

    # Should return immediately without any HTTP requests (hits line 96)
    result = @client.send(:discover_calendar_url, "TestCalendar")

    assert_equal(cached_url, result)
  ensure
    @client.unstub(:cached_collection_url)
  end

  test "upsert_event hits line 32 fallback PUT without If-Match" do
    stub_discovery

    # First PUT 412
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .with(headers: { "If-None-Match" => "*" })
      .to_return(status: 412)

    # HEAD request returns no ETag (or fails)
    stub_request(:head, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .to_return(status: 200, headers: {})

    # Second PUT without If-Match or If-None-Match headers (this is line 32)
    stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .with { |request| !request.headers.key?("If-Match") && !request.headers.key?("If-None-Match") }
      .to_return(status: 204)

    payload = { uid: "abc123", title: "Test", starts_at: Time.utc(2025, 1, 1, 10), ends_at: Time.utc(2025, 1, 1, 11) }

    result = @client.upsert_event(calendar_identifier: "Work", payload: payload)

    assert_equal("abc123", result)
  end

  test "delete_event hits line 57 else raise for non-404 errors" do
    # Mock cached_collection_url to avoid discovery
    @client.stubs(:cached_collection_url).returns("https://caldav.example.test/calendars/user/Work/")

    # Mock the request method to raise an exception with non-404 message
    # This should trigger the rescue block and hit line 57 (else + raise)
    @client.stubs(:request).raises(RuntimeError, "CalDAV DELETE failed: 500 Internal Server Error")

    # This should hit line 57: raise (in the else clause after checking for 404)
    error = assert_raises(RuntimeError) do
      @client.delete_event(calendar_identifier: "Work", uid: "abc123")
    end

    assert_match(/CalDAV DELETE.*failed: 500/, error.message)
  ensure
    @client.unstub(:request)
    @client.unstub(:cached_collection_url)
  end

  private

  def caldav_key(identifier)
    "apple:caldav:collection_url:#{@creds[:username]}:#{identifier}"
  end

  def seed_cache(identifier, url:)
    Rails.cache.write(caldav_key(identifier), url)
  end

  def stub_discovery(identifier: "Work")
    stub_discovery_for(identifier)
  end

  def stub_discovery_for(identifier)
    base = @creds[:base_url]
    stub_request(:propfind, "#{base}/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "#{base}/principals/user/" }, body: "")

    stub_request(:propfind, "#{base}/principals/user/")
      .with(headers: { "Depth" => "0" })
      .to_return(status: 207, body: <<~XML)
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response><d:propstat><d:prop><cal:calendar-home-set><d:href>/calendars/user/</d:href></cal:calendar-home-set></d:prop></d:propstat></d:response>
        </d:multistatus>
      XML

    stub_request(:propfind, "#{base}/calendars/user/")
      .with(headers: { "Depth" => "1" })
      .to_return(status: 207, body: <<~XML)
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/calendars/user/#{identifier}/</d:href>
            <d:propstat><d:prop><d:displayname>#{identifier}</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
      XML
  end
end
