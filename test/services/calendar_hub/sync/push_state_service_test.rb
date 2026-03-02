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

      test "pushes upcoming events to Apple Calendar" do
        upcoming_events = @source.calendar_events.upcoming
        @observer.expects(:start).with(total: upcoming_events.size)
        @observer.expects(:finish).with(status: :success)

        syncer = mock("AppleEventSyncer")
        syncer.expects(:sync_events_batch).with(anything, observer: @observer).returns({ upserts: 2, deletes: 0 })
        CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: @source, apple_client: @apple_client).returns(syncer)

        service = PushStateService.new(source: @source, apple_client: @apple_client, observer: @observer)
        counts = service.call

        assert_equal 2, counts[:upserts]
        assert_equal 0, counts[:deletes]
      end

      test "returns zero counts when no upcoming events" do
        @source.calendar_events.update_all(starts_at: 2.days.ago, ends_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

        @observer.expects(:start).with(total: 0)
        @observer.expects(:finish).with(status: :success)

        syncer = mock("AppleEventSyncer")
        syncer.expects(:sync_events_batch).returns({ upserts: 0, deletes: 0 })
        CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: @source, apple_client: @apple_client).returns(syncer)

        service = PushStateService.new(source: @source, apple_client: @apple_client, observer: @observer)
        counts = service.call

        assert_equal 0, counts[:upserts]
        assert_equal 0, counts[:deletes]
      end
    end
  end
end
