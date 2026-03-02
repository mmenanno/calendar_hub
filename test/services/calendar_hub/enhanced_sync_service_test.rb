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

    test "skips sync when feed returns not modified" do
      @adapter.expects(:respond_to?).with(:fetch_events_with_change_detection).returns(true)
      @adapter.expects(:fetch_events_with_change_detection).returns({ changed: false, events: [] })
      @source.expects(:mark_synced!).with(token: anything, timestamp: anything)
      @observer.expects(:finish).with(status: :success)

      result = @service.call

      assert_empty result
    end

    test "updates last_synced_at when feed returns not modified" do
      source = calendar_sources(:provider)
      source.update_columns(last_synced_at: 3.days.ago, sync_token: "old-token") # rubocop:disable Rails/SkipsModelValidations

      adapter = mock("EnhancedIcsAdapter")
      adapter.expects(:respond_to?).with(:fetch_events_with_change_detection).returns(true)
      adapter.expects(:fetch_events_with_change_detection).returns({ changed: false, events: [] })

      observer = mock("Observer")
      observer.expects(:finish).with(status: :success)

      service = ::CalendarHub::Sync::EnhancedSyncService.new(
        source: source,
        apple_client: @apple_client,
        observer: observer,
        adapter: adapter,
      )

      result = service.call

      assert_empty result
      source.reload

      assert_in_delta Time.current, source.last_synced_at, 5.seconds
    end

    test "performs full sync when feed has changes" do
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
  end
end
