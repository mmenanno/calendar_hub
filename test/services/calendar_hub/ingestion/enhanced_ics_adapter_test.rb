# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

module CalendarHub
  module Ingestion
    class EnhancedICSAdapterTest < ActiveSupport::TestCase
      setup do
        @source = calendar_sources(:provider)
        @adapter = CalendarHub::Ingestion::EnhancedICSAdapter.new(@source)
        WebMock.disable_net_connect!
      end

      teardown do
        WebMock.allow_net_connect!
      end

      test "fetch_events_with_change_detection returns not changed for 304" do
        stub_request(:get, @source.ingestion_url)
          .to_return(status: 304)

        result = @adapter.fetch_events_with_change_detection

        refute result[:changed]
        assert_empty result[:events]
      end

      test "fetch_events_with_change_detection returns changed for 200" do
        ics_content = <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:test
          BEGIN:VEVENT
          UID:test-event-1
          DTSTART:20250925T100000Z
          DTEND:20250925T110000Z
          SUMMARY:Test Event
          END:VEVENT
          END:VCALENDAR
        ICS

        stub_request(:get, @source.ingestion_url)
          .to_return(
            status: 200,
            body: ics_content,
            headers: {
              "ETag" => '"abc123"',
              "Last-Modified" => "Wed, 25 Sep 2025 10:00:00 GMT",
            },
          )

        result = @adapter.fetch_events_with_change_detection

        assert result[:changed]
        assert_equal 1, result[:events].count

        @source.reload

        assert_equal '"abc123"', @source.ics_feed_etag
        assert_equal "Wed, 25 Sep 2025 10:00:00 GMT", @source.ics_feed_last_modified
      end

      test "fetch_events_with_change_detection sends If-None-Match header" do
        @source.update!(ics_feed_etag: '"previous-etag"')

        stub = stub_request(:get, @source.ingestion_url)
          .with(headers: { "If-None-Match" => '"previous-etag"' })
          .to_return(status: 304)

        result = @adapter.fetch_events_with_change_detection

        assert_requested(stub)
        assert_equal({ changed: false, events: [] }, result, "Should return unchanged result for 304 Not Modified response")
      end

      test "fetch_events_with_change_detection sends If-Modified-Since header" do
        @source.update!(ics_feed_last_modified: "Wed, 24 Sep 2025 10:00:00 GMT")

        stub = stub_request(:get, @source.ingestion_url)
          .with(headers: { "If-Modified-Since" => "Wed, 24 Sep 2025 10:00:00 GMT" })
          .to_return(status: 304)

        result = @adapter.fetch_events_with_change_detection

        assert_requested(stub)
        assert_equal({ changed: false, events: [] }, result, "Should return unchanged result for 304 Not Modified response")
      end

      test "has_changes detects mapping changes" do
        @source.update!(last_change_hash: "old-hash")
        @source.event_mappings.create!(pattern: "test", replacement: "new")

        # Mock the feed check to return not changed
        stub_request(:get, @source.ingestion_url)
          .to_return(status: 304)

        assert_predicate @adapter, :has_changes?
      end

      test "has_changes detects feed changes" do
        @source.update!(last_change_hash: @source.generate_change_hash)

        ics_content = <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:test
          BEGIN:VEVENT
          UID:test-event-1
          DTSTART:20250925T100000Z
          DTEND:20250925T110000Z
          SUMMARY:Test Event
          END:VEVENT
          END:VCALENDAR
        ICS

        stub_request(:get, @source.ingestion_url)
          .to_return(status: 200, body: ics_content, headers: { "ETag" => '"new-etag"' })

        assert_predicate @adapter, :has_changes?
      end

      test "has_changes returns false when nothing changed" do
        @source.update!(last_change_hash: @source.generate_change_hash)

        stub_request(:get, @source.ingestion_url)
          .to_return(status: 304)

        refute_predicate @adapter, :has_changes?
      end

      test "handles HTTP errors gracefully" do
        stub_request(:get, @source.ingestion_url)
          .to_return(status: 500, body: "Internal Server Error")

        assert_raises CalendarHub::Ingestion::Error do
          @adapter.fetch_events_with_change_detection
        end
      end
    end
  end
end
