# frozen_string_literal: true

require "test_helper"

class AppleCalendarClientTest < ActiveSupport::TestCase
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
    stub_discovery

    # Upsert stub
    stub = stub_request(:put, "https://caldav.example.test/calendars/user/Work/abc123.ics")
      .with(headers: { "Content-Type" => %r{text/calendar} })
      .to_return(status: 201)

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
    # Defensive stubs in case discovery is still attempted (should not be used)
    stub_request(:propfind, "https://caldav.example.test/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "https://caldav.example.test/principals/user/" }, body: "")
    stub_request(:propfind, "https://caldav.example.test/principals/user/").to_return(status: 207, body: "<d:multistatus xmlns:d=\"DAV:\" xmlns:cal=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:propstat><d:prop><cal:calendar-home-set><d:href>/calendars/user/</d:href></cal:calendar-home-set></d:prop></d:propstat></d:response></d:multistatus>")
    stub_request(:propfind, "https://caldav.example.test/calendars/user/").to_return(status: 207, body: "<d:multistatus xmlns:d=\"DAV:\" xmlns:cal=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:href>/calendars/user/Work/</d:href><d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop></d:propstat></d:response></d:multistatus>")
    stub = stub_request(:delete, "https://caldav.example.test/calendars/user/Work/abc123.ics").to_return(status: 204)
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

  private

  def caldav_key(identifier)
    "apple:caldav:collection_url:#{@creds[:username]}:#{identifier}"
  end

  def seed_cache(identifier, url:)
    Rails.cache.write(caldav_key(identifier), url)
  end

  def stub_discovery(identifier: "Work")
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
