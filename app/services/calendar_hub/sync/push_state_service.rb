# frozen_string_literal: true

module CalendarHub
  module Sync
    class PushStateService
      attr_reader :source, :apple_syncer, :observer

      def initialize(source:, apple_client: AppleCalendar::Client.new, observer: nil)
        @source = source
        @apple_syncer = ::CalendarHub::Shared::AppleEventSyncer.new(source: source, apple_client: apple_client)
        @observer = observer || ::CalendarHub::Shared::NullObserver.new
      end

      def call
        events = source.calendar_events.upcoming
        observer.start(total: events.size)
        counts = apple_syncer.sync_events_batch(events, observer: observer)
        observer.finish(status: :success)
        counts
      end
    end
  end
end
