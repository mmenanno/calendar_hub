# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class PurgeServiceTest < ActiveSupport::TestCase
    test "purges source and all related records" do
      source = calendar_sources(:ics_feed)
      event = CalendarEvent.create!(calendar_source: source, external_id: "e1", title: "t", starts_at: Time.current, ends_at: 1.hour.from_now)
      attempt = SyncAttempt.create!(calendar_source: source, status: :queued)
      audit = CalendarEventAudit.create!(calendar_event: event, action: :created, occurred_at: Time.current)
      sync_result = SyncEventResult.create!(sync_attempt: attempt, external_id: "e1", action: "upsert", success: true, occurred_at: Time.current)
      event_mapping = EventMapping.create!(calendar_source: source, pattern: "title", replacement: "summary", match_type: "contains")

      service = ::CalendarHub::PurgeService.new(source)
      result = service.call

      assert_nil(CalendarSource.unscoped.find_by(id: source.id))
      assert_nil(CalendarEvent.find_by(id: event.id))
      assert_nil(SyncAttempt.find_by(id: attempt.id))
      assert_nil(CalendarEventAudit.find_by(id: audit.id))
      assert_nil(SyncEventResult.find_by(id: sync_result.id))
      assert_nil(EventMapping.find_by(id: event_mapping.id))

      assert_kind_of(Hash, result)
    end

    test "handles source that doesn't exist" do
      service = ::CalendarHub::PurgeService.new(nil)
      result = service.call

      assert_nil(result)
    end

    test "logs purge activity" do
      source = calendar_sources(:ics_feed)
      service = ::CalendarHub::PurgeService.new(source)

      Rails.logger.expects(:info).with(regexp_matches(/Starting purge for source/))
      Rails.logger.expects(:info).with(regexp_matches(/Completed purge for source/))

      service.call
    end
  end
end
