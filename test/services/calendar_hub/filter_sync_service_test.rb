# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Sync
    class FilterSyncServiceTest < ActiveSupport::TestCase
      def setup
        @source = calendar_sources(:provider)
        @apple_client_mock = mock("AppleCalendar::Client")
        @service = ::CalendarHub::Sync::FilterSyncService.new(source: @source, apple_client: @apple_client_mock)
        @service_with_default_client = ::CalendarHub::Sync::FilterSyncService.new(source: @source)
      end

      test "initialize sets source and apple_client" do
        assert_equal(@source, @service.source)
        assert_equal(@apple_client_mock, @service.apple_client)
      end

      test "initialize uses default AppleCalendar::Client when not provided" do
        AppleCalendar::Client.expects(:new).returns(@apple_client_mock)
        service = ::CalendarHub::Sync::FilterSyncService.new(source: @source)

        assert_equal(@source, service.source)
        assert_equal(@apple_client_mock, service.apple_client)
      end

      test "sync_filter_rules returns zeros when source is blank" do
        service = ::CalendarHub::Sync::FilterSyncService.new(source: nil, apple_client: @apple_client_mock)
        result = service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 0 }, result)
      end

      test "sync_filter_rules returns counts when no changes needed" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(0)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(0)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 0 }, result)
      end

      test "sync_filter_rules triggers apple sync when filtered_count > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(5)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(0)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 5, re_included: 0 }, result)
      end

      test "sync_filter_rules triggers apple sync when re_included_count > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(0)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(3)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 3 }, result)
      end

      test "sync_filter_rules triggers apple sync when both counts > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(2)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(1)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 2, re_included: 1 }, result)
      end

      test "sync_event_filter_status returns early when event calendar_source differs" do
        event = calendar_events(:provider_consult)
        different_source = calendar_sources(:ics_feed)
        event.stubs(:calendar_source).returns(different_source)

        @apple_client_mock.expects(:delete_event).never
        @apple_client_mock.expects(:upsert_event).never

        @service.sync_event_filter_status(event)
      end

      test "sync_event_filter_status deletes event when sync_exempt" do
        event = calendar_events(:provider_consult)
        event.stubs(:calendar_source).returns(@source)
        event.stubs(:sync_exempt?).returns(true)
        event.expects(:mark_synced!)

        expected_uid = "prov-123@#{@source.id}.calendar-hub.local"
        @apple_client_mock.expects(:delete_event).with(
          calendar_identifier: @source.calendar_identifier,
          uid: expected_uid,
        )

        @service.sync_event_filter_status(event)
      end

      test "sync_event_filter_status upserts event when not sync_exempt" do
        event = calendar_events(:provider_consult)
        event.stubs(:calendar_source).returns(@source)
        event.stubs(:sync_exempt?).returns(false)
        event.expects(:mark_synced!)

        # The FilterAppleEventSyncer handles all the payload building internally
        # We just verify the final upsert call with the correct filter UID format
        @apple_client_mock.expects(:upsert_event).with do |args|
          args[:calendar_identifier] == @source.calendar_identifier &&
            args[:payload][:uid] == "prov-123@#{@source.id}.calendar-hub.local"
        end

        @service.sync_event_filter_status(event)
      end

      test "sync_event_filter_status handles StandardError and re-raises" do
        event = calendar_events(:provider_consult)
        event.stubs(:calendar_source).returns(@source)
        event.stubs(:sync_exempt?).returns(true)

        error_message = "Apple Calendar API Error"
        @apple_client_mock.expects(:delete_event).raises(StandardError.new(error_message))

        Rails.logger.expects(:error).with("[FilterSync] Failed to sync event #{event.id}: #{error_message}")

        assert_raises(StandardError) do
          @service.sync_event_filter_status(event)
        end
      end

      test "sync_event_filter_status handles StandardError during upsert and re-raises" do
        event = calendar_events(:provider_consult)
        event.stubs(:calendar_source).returns(@source)
        event.stubs(:sync_exempt?).returns(false)

        error_message = "Apple Calendar upsert failed"
        @apple_client_mock.expects(:upsert_event).raises(StandardError.new(error_message))

        Rails.logger.expects(:error).with("[FilterSync] Failed to sync event #{event.id}: #{error_message}")

        assert_raises(StandardError) do
          @service.sync_event_filter_status(event)
        end
      end

      test "sync_event_filter_status with nil event returns early" do
        @apple_client_mock.expects(:delete_event).never
        @apple_client_mock.expects(:upsert_event).never

        @service.sync_event_filter_status(nil)
      end

      test "trigger_apple_sync calls schedule_sync with force: true" do
        @source.expects(:schedule_sync).with(force: true)
        @service.send(:trigger_apple_sync)
      end

      test "composite_uid_for generates correct uid" do
        event = calendar_events(:provider_consult)
        expected_uid = "prov-123@#{@source.id}.calendar-hub.local"

        assert_equal(expected_uid, @service.send(:composite_uid_for, event))
      end

      test "event_url_for generates correct url" do
        event = calendar_events(:provider_consult)
        expected_url = "https://example.com/events/#{event.id}"
        url_options = { host: "localhost", protocol: "http" }

        UrlOptions.expects(:for_links).returns(url_options)
        Rails.application.routes.url_helpers.expects(:calendar_event_url).with(
          event,
          **url_options,
        ).returns(expected_url)

        assert_equal(expected_url, @service.send(:event_url_for, event))
      end
    end
  end
end
