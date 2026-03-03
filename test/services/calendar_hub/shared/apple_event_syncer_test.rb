# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Shared
    class AppleEventSyncerTest < ActiveSupport::TestCase
      include ModelBuilders
      include MochaHelpers

      setup do
        @source = calendar_sources(:provider)
        @apple_client = mock_apple_client
        @syncer = AppleEventSyncer.new(source: @source, apple_client: @apple_client)
      end

      test "sync_event records last_synced_to_calendar after successful upsert" do
        event = build_event(calendar_source: @source)
        @apple_client.stubs(:upsert_event)

        @syncer.sync_event(event)

        assert_equal @source.calendar_identifier, event.reload.last_synced_to_calendar
      end

      test "sync_event records last_synced_to_calendar after successful delete" do
        event = build_event(calendar_source: @source, sync_exempt: true)
        @apple_client.stubs(:delete_event)

        @syncer.sync_event(event)

        assert_equal @source.calendar_identifier, event.reload.last_synced_to_calendar
      end

      test "sync_event deletes from old calendar when destination changes" do
        override_calendar = "Michael Personal"
        event = build_event(
          calendar_source: @source,
          title: "Michael Appointment",
          last_synced_to_calendar: @source.calendar_identifier,
        )

        # Set up a mapping that routes "Michael" events to a different calendar
        EventMapping.create!(
          calendar_source: @source,
          pattern: "Michael",
          match_type: "contains",
          case_sensitive: false,
          target_calendar_identifier: override_calendar,
          active: true,
          position: 0,
        )

        # Expect delete from OLD calendar, then upsert to NEW calendar
        delete_seq = sequence("destination_change")
        @apple_client.expects(:delete_event).with(
          calendar_identifier: @source.calendar_identifier,
          uid: UidGenerator.composite_uid_for(event),
        ).in_sequence(delete_seq)
        @apple_client.expects(:upsert_event).with do |args|
          args[:calendar_identifier] == override_calendar
        end.in_sequence(delete_seq)

        result = @syncer.sync_event(event)

        assert_equal :upserted, result
        assert_equal override_calendar, event.reload.last_synced_to_calendar
      end

      test "sync_event does not delete from old calendar when destination is unchanged" do
        event = build_event(
          calendar_source: @source,
          last_synced_to_calendar: @source.calendar_identifier,
        )

        # No destination override mapping — destination stays as source default
        @apple_client.expects(:delete_event).never
        @apple_client.expects(:upsert_event).once

        @syncer.sync_event(event)
      end

      test "sync_event does not delete from old calendar on first sync (nil last_synced_to_calendar)" do
        event = build_event(calendar_source: @source)
        assert_nil event.last_synced_to_calendar

        @apple_client.expects(:delete_event).never
        @apple_client.expects(:upsert_event).once

        @syncer.sync_event(event)

        assert_equal @source.calendar_identifier, event.reload.last_synced_to_calendar
      end

      test "sync_event deletes from override calendar when routing removed" do
        override_calendar = "Michael Personal"
        event = build_event(
          calendar_source: @source,
          title: "Regular Appointment",
          last_synced_to_calendar: override_calendar,
        )

        # No mapping exists — event routes back to source default
        # Should delete from override, then upsert to default
        delete_seq = sequence("routing_removed")
        @apple_client.expects(:delete_event).with(
          calendar_identifier: override_calendar,
          uid: UidGenerator.composite_uid_for(event),
        ).in_sequence(delete_seq)
        @apple_client.expects(:upsert_event).with do |args|
          args[:calendar_identifier] == @source.calendar_identifier
        end.in_sequence(delete_seq)

        result = @syncer.sync_event(event)

        assert_equal :upserted, result
        assert_equal @source.calendar_identifier, event.reload.last_synced_to_calendar
      end

      test "sync_event continues if cleanup delete from old calendar fails" do
        event = build_event(
          calendar_source: @source,
          title: "Michael Appointment",
          last_synced_to_calendar: "Old Calendar",
        )

        EventMapping.create!(
          calendar_source: @source,
          pattern: "Michael",
          match_type: "contains",
          case_sensitive: false,
          target_calendar_identifier: "New Calendar",
          active: true,
          position: 0,
        )

        # Cleanup delete fails (e.g., 404 for already-deleted event)
        @apple_client.expects(:delete_event).with(
          calendar_identifier: "Old Calendar",
          uid: UidGenerator.composite_uid_for(event),
        ).raises(StandardError.new("CalDAV DELETE failed: 404 Not Found"))

        # Upsert to new destination still proceeds
        @apple_client.expects(:upsert_event).with do |args|
          args[:calendar_identifier] == "New Calendar"
        end

        result = @syncer.sync_event(event)

        assert_equal :upserted, result
        assert_equal "New Calendar", event.reload.last_synced_to_calendar
      end

      test "sync_event does not update last_synced_to_calendar on error" do
        event = build_event(
          calendar_source: @source,
          last_synced_to_calendar: @source.calendar_identifier,
        )

        @apple_client.expects(:upsert_event).raises(StandardError.new("CalDAV PUT failed"))

        result = @syncer.sync_event(event)

        assert_equal :error, result
        # Should still have the old value
        assert_equal @source.calendar_identifier, event.reload.last_synced_to_calendar
      end
    end
  end
end
