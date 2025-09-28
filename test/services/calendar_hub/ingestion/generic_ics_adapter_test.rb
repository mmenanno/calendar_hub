# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Ingestion
    class GenericICSAdapterTest < ActiveSupport::TestCase
      include WebMockHelpers

      setup do
        @source = calendar_sources(:ics_feed)
        @ics_body = file_fixture("provider.ics").read
        stub_ics_request(@source, body: @ics_body)
      end

      test "parses events from ics feed" do
        adapter = GenericICSAdapter.new(@source)
        events = adapter.fetch_events

        assert_equal 2, events.count
        first = events.first

        assert_equal "prov-123", first.uid
        assert_equal "Initial Consultation", first.summary
        assert_equal "confirmed", first.status
        assert_kind_of Hash, first.raw_properties
      end

      test "raises error when url missing" do
        @source.ingestion_url = nil
        adapter = GenericICSAdapter.new(@source)
        assert_raises(Ingestion::Error) { adapter.fetch_events }
      end

      test "returns empty when server responds 304 Not Modified" do
        stub_ics_304_not_modified(@source)
        adapter = GenericICSAdapter.new(@source)
        events = adapter.fetch_events

        assert_equal 0, events.size
      end

      test "stores etag and last-modified headers" do
        stub_ics_request(
          @source,
          body: @ics_body,
          headers: { "ETag" => '"abc123"', "Last-Modified" => "Wed, 21 Oct 2015 07:28:00 GMT" },
        )

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        @source.reload

        assert_equal('"abc123"', @source.settings["etag"])
        assert_equal("Wed, 21 Oct 2015 07:28:00 GMT", @source.settings["last_modified"])
      end

      test "sends conditional headers when available" do
        @source.settings["etag"] = '"existing-etag"'
        @source.settings["last_modified"] = "Tue, 20 Oct 2015 07:28:00 GMT"
        @source.save!

        stub = stub_request(:get, @source.ingestion_url)
          .with(headers: { "If-None-Match" => '"existing-etag"', "If-Modified-Since" => "Tue, 20 Oct 2015 07:28:00 GMT" })
          .to_return(status: 200, body: @ics_body)

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        assert_requested(stub)
      end

      test "raises error for unexpected status codes" do
        stub_ics_error(@source, status: 500, message: "Internal Server Error")

        adapter = GenericICSAdapter.new(@source)

        error = assert_raises(CalendarHub::Ingestion::Error) do
          adapter.fetch_events
        end

        assert_match(/the server responded with status 500/, error.message)
      end

      test "fetch_ics_body raises error for unexpected status codes" do
        adapter = GenericICSAdapter.new(@source)

        # Mock the http_client to return a response that bypasses Faraday's raise_error middleware
        mock_response = mock("response")
        mock_response.stubs(:status).returns(418) # I'm a teapot - unexpected status
        mock_response.stubs(:headers).returns({})

        mock_client = mock("http_client")
        mock_client.expects(:get).with(@source.ingestion_url).returns(mock_response)

        adapter.stubs(:http_client).returns(mock_client)

        error = assert_raises(CalendarHub::Ingestion::Error) do
          adapter.send(:fetch_ics_body)
        end

        assert_match(/Unexpected response status: 418/, error.message)
      ensure
        adapter.unstub(:http_client) if adapter.respond_to?(:unstub)
      end

      test "handles Faraday errors" do
        stub_request(:get, @source.ingestion_url).to_raise(Faraday::ConnectionFailed.new("Connection failed"))

        adapter = GenericICSAdapter.new(@source)

        error = assert_raises(CalendarHub::Ingestion::Error) do
          adapter.fetch_events
        end

        assert_match(/Connection failed/, error.message)
      end

      test "filters events by import_start_date" do
        @source.import_start_date = Date.parse("2025-01-15")
        @source.save!

        # Create ICS with events before and after the import_start_date
        ics_with_mixed_dates = <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:old-event
          DTSTART:20250110T100000Z
          DTEND:20250110T110000Z
          SUMMARY:Old Event
          END:VEVENT
          BEGIN:VEVENT
          UID:new-event
          DTSTART:20250120T100000Z
          DTEND:20250120T110000Z
          SUMMARY:New Event
          END:VEVENT
          END:VCALENDAR
        ICS

        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: ics_with_mixed_dates)

        adapter = GenericICSAdapter.new(@source)
        events = adapter.fetch_events

        assert_equal(1, events.size)
        assert_equal("new-event", events.first.uid)
        assert_equal("New Event", events.first.summary)
      end

      test "applies HTTP basic authentication when credentials provided" do
        @source.credentials = { http_basic_username: "user", http_basic_password: "pass" }
        @source.save!

        stub = stub_request(:get, @source.ingestion_url)
          .with(basic_auth: ["user", "pass"])
          .to_return(status: 200, body: @ics_body)

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        assert_requested(stub)
      end

      test "skips authentication when credentials are blank" do
        @source.credentials = { http_basic_username: "", http_basic_password: "" }
        @source.save!

        stub = stub_request(:get, @source.ingestion_url)
          .to_return(status: 200, body: @ics_body)

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        assert_requested(stub)
      end

      test "skips authentication when no credentials provided" do
        @source.credentials = nil
        @source.save!

        stub = stub_request(:get, @source.ingestion_url)
          .to_return(status: 200, body: @ics_body)

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        assert_requested(stub)
      end

      test "sets correct user agent header" do
        stub = stub_request(:get, @source.ingestion_url)
          .with(headers: { "User-Agent" => "CalendarHub/1.0" })
          .to_return(status: 200, body: @ics_body)

        adapter = GenericICSAdapter.new(@source)
        adapter.fetch_events

        assert_requested(stub)
      end

      test "to_fetched_event creates proper event object" do
        adapter = GenericICSAdapter.new(@source)

        # Create a mock ICS event using Struct
        MockEventStruct = Struct.new(:uid, :summary, :description, :location, :starts_at, :ends_at, :status, :all_day, :raw_properties)
        mock_event = MockEventStruct.new(
          "test-123",
          "Test Event",
          "Test Description",
          "Test Location",
          Time.zone.parse("2025-01-01 10:00"),
          Time.zone.parse("2025-01-01 11:00"),
          "CONFIRMED",
          false,
          { "X-CUSTOM" => "value" },
        )

        result = adapter.send(:to_fetched_event, mock_event)

        assert_equal("test-123", result.uid)
        assert_equal("Test Event", result.summary)
        assert_equal("Test Description", result.description)
        assert_equal("Test Location", result.location)
        assert_equal(Time.zone.parse("2025-01-01 10:00"), result.starts_at)
        assert_equal(Time.zone.parse("2025-01-01 11:00"), result.ends_at)
      end

      test "to_fetched_event sets correct status and metadata" do
        adapter = GenericICSAdapter.new(@source)

        MockEventStruct2 = Struct.new(:uid, :summary, :description, :location, :starts_at, :ends_at, :status, :all_day, :raw_properties)
        mock_event = MockEventStruct2.new(
          "test-123",
          "Test Event",
          "Test Description",
          "Test Location",
          Time.zone.parse("2025-01-01 10:00"),
          Time.zone.parse("2025-01-01 11:00"),
          "CONFIRMED",
          false,
          { "X-CUSTOM" => "value" },
        )

        result = adapter.send(:to_fetched_event, mock_event)

        assert_equal("confirmed", result.status)
        refute(result.all_day)
        assert_equal(@source.time_zone, result.time_zone)
        assert_equal({ "X-CUSTOM" => "value" }, result.raw_properties)
      end

      test "to_fetched_event handles blank summary" do
        adapter = GenericICSAdapter.new(@source)

        MockEventStruct3 = Struct.new(:uid, :summary, :description, :location, :starts_at, :ends_at, :status, :all_day, :raw_properties)
        mock_event = MockEventStruct3.new(
          "test-123",
          "",
          nil,
          nil,
          Time.zone.parse("2025-01-01 10:00"),
          Time.zone.parse("2025-01-01 11:00"),
          nil,
          nil,
          nil,
        )

        result = adapter.send(:to_fetched_event, mock_event)

        assert_equal("(untitled event)", result.summary)
        assert_nil(result.description)
        assert_nil(result.location)
        assert_equal("confirmed", result.status)
        refute(result.all_day)
        assert_nil(result.raw_properties)
      end

      test "normalized_status handles cancelled status" do
        adapter = GenericICSAdapter.new(@source)

        assert_equal("cancelled", adapter.send(:normalized_status, "CANCELLED"))
        assert_equal("cancelled", adapter.send(:normalized_status, "cancelled"))
      end

      test "normalized_status handles tentative status" do
        adapter = GenericICSAdapter.new(@source)

        assert_equal("tentative", adapter.send(:normalized_status, "TENTATIVE"))
        assert_equal("tentative", adapter.send(:normalized_status, "tentative"))
      end

      test "normalized_status handles confirmed and default status" do
        adapter = GenericICSAdapter.new(@source)

        assert_equal("confirmed", adapter.send(:normalized_status, "CONFIRMED"))
        assert_equal("confirmed", adapter.send(:normalized_status, "confirmed"))
        assert_equal("confirmed", adapter.send(:normalized_status, "unknown"))
        assert_equal("confirmed", adapter.send(:normalized_status, nil))
      end
    end
  end
end
