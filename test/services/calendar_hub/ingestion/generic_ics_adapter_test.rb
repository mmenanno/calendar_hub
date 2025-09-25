# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Ingestion
    class GenericICSAdapterTest < ActiveSupport::TestCase
      setup do
        @source = calendar_sources(:ics_feed)
        @ics_body = file_fixture("provider.ics").read
        stub_request(:get, @source.ingestion_url).to_return(status: 200, body: @ics_body)
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
        # Override stub for delta path
        stub_request(:get, @source.ingestion_url).to_return(status: 304, body: "")
        adapter = GenericICSAdapter.new(@source)
        events = adapter.fetch_events

        assert_equal 0, events.size
      end
    end
  end
end
