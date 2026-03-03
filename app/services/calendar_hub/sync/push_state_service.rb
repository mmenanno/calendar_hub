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
        relation = source.calendar_events.upcoming
        total = relation.count
        observer.start(total: total)

        upserts = 0
        deletes = 0

        relation.find_each(batch_size: 500) do |event|
          result = apple_syncer.sync_event(event, observer: observer)
          case result
          when :upserted then upserts += 1
          when :deleted then deletes += 1
          end
        end

        observer.finish(status: :success)
        { upserts: upserts, deletes: deletes }
      end
    end
  end
end
