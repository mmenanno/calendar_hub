# frozen_string_literal: true

class SyncEventToAppleJob < ApplicationJob
  queue_as :sync

  def perform(calendar_event_id)
    event = CalendarEvent.find(calendar_event_id)
    source = event.calendar_source
    return unless source&.active?

    client = AppleCalendar::Client.new
    CalendarHub::Shared::AppleEventSyncer.new(source: source, apple_client: client).sync_event(event)
  ensure
    client&.finish
  end
end
