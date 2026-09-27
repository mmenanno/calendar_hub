# frozen_string_literal: true

module CalendarHub
  class PurgeService
    class RemoteCleanupError < StandardError
    end

    # Define the order of deletion to respect foreign key constraints
    DEPENDENT_MODELS = [
      { model: SyncEventResult, scope: ->(source) { SyncEventResult.joins(:sync_attempt).where(sync_attempts: { calendar_source_id: source.id }) } },
      { model: SyncEventResult, scope: ->(source) { SyncEventResult.joins(:calendar_event).where(calendar_events: { calendar_source_id: source.id }) } },
      { model: CalendarEventAudit, scope: ->(source) { CalendarEventAudit.joins(:calendar_event).where(calendar_events: { calendar_source_id: source.id }) } },
      { model: SyncAttempt, scope: ->(source) { SyncAttempt.where(calendar_source_id: source.id) } },
      { model: CalendarEvent, scope: ->(source) { CalendarEvent.where(calendar_source_id: source.id) } },
      { model: EventMapping, scope: ->(source) { EventMapping.where(calendar_source_id: source.id) } },
    ].freeze

    def initialize(source, apple_client: nil)
      @source = source
      @apple_client = apple_client
    end

    # Deletes the source's events from Apple Calendar, then its rows. Raises
    # RemoteCleanupError (before touching any rows) when some iCloud deletes
    # failed, so the caller can retry; pass remote_cleanup: false to purge
    # the rows regardless.
    def call(remote_cleanup: true)
      return unless @source

      Rails.logger.info("[PurgeService] Starting purge for source #{@source.id}")
      delete_remote_events! if remote_cleanup

      deleted_counts = {}
      DEPENDENT_MODELS.each do |config|
        count = config[:scope].call(@source).delete_all
        deleted_counts[config[:model].name] = count if count.positive?
      end

      @source.destroy!

      Rails.logger.info("[PurgeService] Completed purge for source #{@source.id}: #{deleted_counts}")
      deleted_counts
    end

    private

    attr_reader :source

    def delete_remote_events!
      client = @apple_client || AppleCalendar::Client.new
      result = ::CalendarHub::Sync::RemoteCleanupService.new(source: source, apple_client: client).call
      return if result.failed.zero?

      raise RemoteCleanupError, "#{result.failed} events of source #{source.id} could not be deleted from iCloud"
    end
  end
end
