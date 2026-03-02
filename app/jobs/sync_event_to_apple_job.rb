# frozen_string_literal: true

class SyncEventToAppleJob < ApplicationJob
  def perform(calendar_event_id)
    event = CalendarEvent.find(calendar_event_id)
    source = event.calendar_source
    return unless source&.active?

    syncer = CalendarHub::Shared::AppleEventSyncer.new(source: source)
    syncer.sync_event(event)
  end
end
