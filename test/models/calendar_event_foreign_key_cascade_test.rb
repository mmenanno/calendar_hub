# frozen_string_literal: true

require "test_helper"

class CalendarEventForeignKeyCascadeTest < ActiveSupport::TestCase
  test "destroying an event with audits and sync results removes them" do
    event = calendar_events(:provider_consult)
    event.update!(title: "Renamed to create an audit")
    attempt = SyncAttempt.create!(calendar_source: event.calendar_source, status: :success)
    result = SyncEventResult.create!(sync_attempt: attempt, calendar_event: event, external_id: event.external_id, action: "upsert", occurred_at: Time.current)

    assert_predicate(CalendarEventAudit.where(calendar_event_id: event.id), :exists?)

    event.destroy!

    refute_predicate(CalendarEventAudit.where(calendar_event_id: event.id), :exists?)
    refute(SyncEventResult.exists?(result.id))
  end

  test "deleting a sync attempt removes its event results" do
    attempt = SyncAttempt.create!(calendar_source: calendar_sources(:provider), status: :success)
    result = attempt.sync_event_results.create!(external_id: "uid-1", action: "upsert", occurred_at: Time.current)

    SyncAttempt.where(id: attempt.id).delete_all

    refute(SyncEventResult.exists?(result.id))
  end
end
