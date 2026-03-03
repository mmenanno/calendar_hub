# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Sync
    class PushStateServiceTest < ActiveSupport::TestCase
      setup do
        @source = calendar_sources(:provider)
        @apple_client = mock("AppleCalendar::Client")
        @observer = mock("Observer")
      end

      test "pushes upcoming events to Apple Calendar using find_each" do
        upcoming_count = @source.calendar_events.upcoming.count
        @observer.expects(:start).with(total: upcoming_count)
        @observer.expects(:finish).with(status: :success)

        syncer = mock("AppleEventSyncer")
        syncer.expects(:sync_event).times(upcoming_count).returns(:upserted)
        CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: @source, apple_client: @apple_client).returns(syncer)

        service = PushStateService.new(source: @source, apple_client: @apple_client, observer: @observer)
        counts = service.call

        assert_equal upcoming_count, counts[:upserts]
        assert_equal 0, counts[:deletes]
      end

      test "returns zero counts when no upcoming events" do
        @source.calendar_events.update_all(starts_at: 2.days.ago, ends_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

        @observer.expects(:start).with(total: 0)
        @observer.expects(:finish).with(status: :success)

        syncer = mock("AppleEventSyncer")
        syncer.expects(:sync_event).never
        CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: @source, apple_client: @apple_client).returns(syncer)

        service = PushStateService.new(source: @source, apple_client: @apple_client, observer: @observer)
        counts = service.call

        assert_equal 0, counts[:upserts]
        assert_equal 0, counts[:deletes]
      end

      test "tracks deleted events in counts" do
        upcoming_count = @source.calendar_events.upcoming.count
        assert upcoming_count > 0, "Need at least one upcoming event for this test"

        @observer.expects(:start).with(total: upcoming_count)
        @observer.expects(:finish).with(status: :success)

        syncer = mock("AppleEventSyncer")
        syncer.expects(:sync_event).times(upcoming_count).returns(:deleted)
        CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: @source, apple_client: @apple_client).returns(syncer)

        service = PushStateService.new(source: @source, apple_client: @apple_client, observer: @observer)
        counts = service.call

        assert_equal 0, counts[:upserts]
        assert_equal upcoming_count, counts[:deletes]
      end
    end
  end
end
