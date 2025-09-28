# frozen_string_literal: true

module CalendarHub
  module Sync
    class FilterSyncService
      attr_reader :source, :apple_syncer, :apple_client

      def initialize(source:, apple_client: AppleCalendar::Client.new)
        @source = source
        @apple_client = apple_client
        @apple_syncer = ::CalendarHub::Shared::FilterAppleEventSyncer.new(source: source, apple_client: apple_client)
      end

      def sync_filter_rules
        return { filtered: 0, re_included: 0 } if source.blank?

        filtered_count = ::CalendarHub::EventFilter.apply_backwards_filtering(source)
        re_included_count = ::CalendarHub::EventFilter.apply_reverse_filtering(source)

        if filtered_count > 0 || re_included_count > 0
          trigger_apple_sync
        end

        { filtered: filtered_count, re_included: re_included_count }
      end

      def sync_event_filter_status(event)
        return unless event&.calendar_source == source

        apple_syncer.sync_event(event)
      rescue StandardError => error
        Rails.logger.error("[FilterSync] Failed to sync event #{event&.id}: #{error.message}")
        raise
      end

      private

      def trigger_apple_sync
        source.schedule_sync(force: true)
      end

      # Backward compatibility methods for tests
      # FilterSyncService used a different UID format than the standardized one
      def composite_uid_for(event)
        "#{event.external_id}@#{source.id}.calendar-hub.local"
      end

      def event_url_for(event)
        Rails.application.routes.url_helpers.calendar_event_url(
          event,
           **::CalendarHub::UrlOptions.for_links,
        )
      rescue
        nil
      end
    end
  end
end
