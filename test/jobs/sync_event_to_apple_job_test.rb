# frozen_string_literal: true

require "test_helper"

class SyncEventToAppleJobTest < ActiveJob::TestCase
  test "syncs event to Apple Calendar" do
    event = calendar_events(:future_event)
    syncer = mock("AppleEventSyncer")
    syncer.expects(:sync_event).with(event)

    CalendarHub::Shared::AppleEventSyncer.expects(:new).with(source: event.calendar_source).returns(syncer)

    SyncEventToAppleJob.perform_now(event.id)
  end

  test "skips sync when source is inactive" do
    event = calendar_events(:future_event)
    event.calendar_source.update_columns(active: false) # rubocop:disable Rails/SkipsModelValidations

    CalendarHub::Shared::AppleEventSyncer.expects(:new).never

    SyncEventToAppleJob.perform_now(event.id)
  end
end
