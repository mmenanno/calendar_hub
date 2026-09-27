# frozen_string_literal: true

require "test_helper"

class RemoveSourceEventsFromAppleJobTest < ActiveJob::TestCase
  setup do
    @source = calendar_sources(:ics_feed)
    @event = CalendarEvent.create!(
      calendar_source: @source,
      external_id: "archived-1",
      title: "t",
      starts_at: Time.current,
      ends_at: 1.hour.from_now,
      last_synced_to_calendar: "shared",
      synced_fingerprint: "abc",
    )
  end

  test "archiving a source enqueues the iCloud cleanup" do
    assert_enqueued_with(job: RemoveSourceEventsFromAppleJob, args: [@source.id]) do
      @source.soft_delete!
    end
  end

  test "deletes archived events from iCloud and forgets their sync state" do
    @source.update_columns(active: false, deleted_at: Time.current)
    client = AppleCalendar::Client.new(credentials: { username: "u", app_specific_password: "p" })
    AppleCalendar::Client.stubs(:new).returns(client)
    client.expects(:delete_event).with(calendar_identifier: "shared", uid: "ch-#{@source.id}-archived-1").once

    RemoveSourceEventsFromAppleJob.perform_now(@source.id)

    @event.reload

    assert_nil(@event.last_synced_to_calendar)
    assert_equal(CalendarHub::Shared::AppleEventSyncer::DELETED_SIGNATURE, @event.synced_fingerprint)
  end

  test "logs and continues when Apple credentials are missing" do
    @source.update_columns(active: false, deleted_at: Time.current)
    AppleCalendar::Client.stubs(:new).returns(AppleCalendar::Client.new(credentials: {}))
    Rails.logger.expects(:warn).with(regexp_matches(/Apple credentials missing/))

    assert_nothing_raised { RemoveSourceEventsFromAppleJob.perform_now(@source.id) }
    assert_equal("shared", @event.reload.last_synced_to_calendar)
  end

  test "does nothing for sources that are no longer archived" do
    AppleCalendar::Client.expects(:new).never

    RemoveSourceEventsFromAppleJob.perform_now(@source.id)
  end
end
