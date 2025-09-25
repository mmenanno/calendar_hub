# frozen_string_literal: true

class PurgeCalendarSourceJob < ApplicationJob
  queue_as :default

  def perform(source_id)
    source = CalendarSource.unscoped.find_by(id: source_id)
    return unless source

    SyncEventResult.where(sync_attempt_id: SyncAttempt.where(calendar_source_id: source.id)).delete_all
    SyncEventResult.where(calendar_event_id: CalendarEvent.where(calendar_source_id: source.id)).delete_all
    CalendarEventAudit.where(calendar_event_id: CalendarEvent.where(calendar_source_id: source.id)).delete_all
    SyncAttempt.where(calendar_source_id: source.id).delete_all
    CalendarEvent.where(calendar_source_id: source.id).delete_all
    EventMapping.where(calendar_source_id: source.id).delete_all
    source.destroy!
  end
end
