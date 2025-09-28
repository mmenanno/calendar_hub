# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class EnhancedSyncServiceTest < ActiveSupport::TestCase
    MockEvent = Struct.new(:uid, :summary, :description, :location, :starts_at, :ends_at, :status, :all_day, :raw_properties)

    setup do
      @source = calendar_sources(:provider)
      @apple_client = mock("AppleCalendar::Client")
      @adapter = mock("EnhancedIcsAdapter")
      @observer = mock("Observer")

      @service = ::CalendarHub::Sync::EnhancedSyncService.new(
        source: @source,
        apple_client: @apple_client,
        observer: @observer,
        adapter: @adapter,
      )
    end

    test "skips sync when no changes detected" do
      @adapter.expects(:respond_to?).with(:has_changes?).returns(true)
      @adapter.expects(:has_changes?).returns(false)
      @observer.expects(:finish).with(status: :success)

      result = @service.call

      assert_empty result
    end

    test "performs full sync when changes detected" do
      events_data = [
        MockEvent.new(
          "event1",
          "Test Event",
          "Test Description",
          "Test Location",
          1.hour.from_now,
          2.hours.from_now,
          "confirmed",
          false,
          {},
        ),
      ]

      @adapter.expects(:respond_to?).with(:has_changes?).returns(true)
      @adapter.expects(:has_changes?).returns(true)
      @adapter.expects(:respond_to?).with(:fetch_events_with_change_detection).returns(true)
      @adapter.expects(:fetch_events_with_change_detection).returns({ changed: true, events: events_data })

      @observer.expects(:start).with(total: 1)
      @observer.expects(:upsert_success).once
      @observer.expects(:delete_success).at_least(0)
      @observer.expects(:finish).with(status: :success)

      @apple_client.expects(:upsert_event).once
      @apple_client.expects(:delete_event).at_least(0)

      @source.expects(:mark_synced!)

      result = @service.call

      assert_equal 1, result.count
    end

    test "uses regular fetch_events when change detection not available" do
      events_data = [
        MockEvent.new(
          "event1",
          "Test Event",
          nil,
          nil,
          1.hour.from_now,
          2.hours.from_now,
          "confirmed",
          false,
          {},
        ),
      ]

      @adapter.expects(:respond_to?).with(:has_changes?).returns(true)
      @adapter.expects(:has_changes?).returns(true)
      @adapter.expects(:respond_to?).with(:fetch_events_with_change_detection).returns(false)
      @adapter.expects(:fetch_events).returns(events_data)

      @observer.expects(:start).with(total: 1)
      @observer.expects(:upsert_success).once
      @observer.expects(:delete_success).at_least(0)
      @observer.expects(:finish).with(status: :success)

      @apple_client.expects(:upsert_event).once
      @apple_client.expects(:delete_event).at_least(0)

      @source.expects(:mark_synced!)

      result = @service.call

      assert_equal 1, result.count
    end

    test "handles feed not modified response" do
      @adapter.expects(:respond_to?).with(:has_changes?).returns(true)
      @adapter.expects(:has_changes?).returns(true)
      @adapter.expects(:respond_to?).with(:fetch_events_with_change_detection).returns(true)
      @adapter.expects(:fetch_events_with_change_detection).returns({ changed: false, events: [] })

      result = @service.call

      assert_empty result
    end
  end
end
