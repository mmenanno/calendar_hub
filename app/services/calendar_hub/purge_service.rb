# frozen_string_literal: true

module CalendarHub
  class PurgeService
    # Define the order of deletion to respect foreign key constraints
    DEPENDENT_MODELS = [
      { model: SyncEventResult, scope: ->(source) { SyncEventResult.joins(:sync_attempt).where(sync_attempts: { calendar_source_id: source.id }) } },
      { model: SyncEventResult, scope: ->(source) { SyncEventResult.joins(:calendar_event).where(calendar_events: { calendar_source_id: source.id }) } },
      { model: CalendarEventAudit, scope: ->(source) { CalendarEventAudit.joins(:calendar_event).where(calendar_events: { calendar_source_id: source.id }) } },
      { model: SyncAttempt, scope: ->(source) { SyncAttempt.where(calendar_source_id: source.id) } },
      { model: CalendarEvent, scope: ->(source) { CalendarEvent.where(calendar_source_id: source.id) } },
      { model: EventMapping, scope: ->(source) { EventMapping.where(calendar_source_id: source.id) } },
    ].freeze

    def initialize(source)
      @source = source
    end

    def call
      return unless @source

      Rails.logger.info("[PurgeService] Starting purge for source #{@source.id}")

      deleted_counts = {}
      DEPENDENT_MODELS.each do |config|
        count = config[:scope].call(@source).delete_all
        deleted_counts[config[:model].name] = count if count > 0
      end

      @source.destroy!

      Rails.logger.info("[PurgeService] Completed purge for source #{@source.id}: #{deleted_counts}")
      deleted_counts
    end

    private

    attr_reader :source
  end
end
