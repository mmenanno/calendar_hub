# frozen_string_literal: true

module CalendarHub
  module Sync
    # Deletes a source's events from Apple Calendar (used when a source is
    # archived or purged). Only events that may exist remotely
    # (last_synced_to_calendar present) are touched; successfully deleted
    # events are marked as no longer synced so un-archiving re-pushes them.
    class RemoteCleanupService
      Result = Data.define(:deleted, :failed, :skipped)

      attr_reader :source, :apple_client

      def initialize(source:, apple_client: AppleCalendar::Client.new)
        @source = source
        @apple_client = apple_client
      end

      def call
        unless apple_client.respond_to?(:configured?) && apple_client.configured?
          Rails.logger.warn("[RemoteCleanup] Apple credentials missing; not removing events of source=#{source.id} from iCloud")
          return Result.new(deleted: 0, failed: 0, skipped: true)
        end

        syncer = ::CalendarHub::Shared::AppleEventSyncer.new(source: source, apple_client: apple_client)
        deleted = 0
        failed = 0

        CalendarEvent.where(calendar_source_id: source.id).where.not(last_synced_to_calendar: nil).find_each do |event|
          syncer.delete_event(event)
          event.update_columns(
            last_synced_to_calendar: nil,
            synced_fingerprint: ::CalendarHub::Shared::AppleEventSyncer::DELETED_SIGNATURE,
          )
          deleted += 1
        rescue StandardError => exception
          failed += 1
          Rails.logger.warn("[RemoteCleanup] Failed to delete #{event.external_id} of source=#{source.id}: #{exception.message}")
        end

        Rails.logger.info("[RemoteCleanup] source=#{source.id} deleted=#{deleted} failed=#{failed}")
        Result.new(deleted: deleted, failed: failed, skipped: false)
      ensure
        apple_client.finish if apple_client.respond_to?(:finish)
      end
    end
  end
end
