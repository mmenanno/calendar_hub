# frozen_string_literal: true

module CalendarHub
  module Sync
    # Re-evaluates filter rules against a source's stored events and, when the
    # effective exclusion of any event changed, schedules a sync so the change
    # is pushed to Apple Calendar through the regular SyncService.
    class FilterSyncService
      attr_reader :source

      def initialize(source:)
        @source = source
      end

      def sync_filter_rules
        return { filtered: 0, re_included: 0 } if source.blank?

        filtered_count = ::CalendarHub::EventFilter.apply_backwards_filtering(source)
        re_included_count = ::CalendarHub::EventFilter.apply_reverse_filtering(source)

        trigger_apple_sync if filtered_count.positive? || re_included_count.positive?

        Rails.logger.info("[FilterSyncService] source=#{source.id} filtered=#{filtered_count} re_included=#{re_included_count}")
        { filtered: filtered_count, re_included: re_included_count }
      rescue StandardError => exception
        Rails.logger.error("[FilterSyncService] Unexpected error during filter sync for source=#{source.id}: #{exception.message}")
        raise
      end

      private

      def trigger_apple_sync
        source.schedule_sync(force: true)
      end
    end
  end
end
