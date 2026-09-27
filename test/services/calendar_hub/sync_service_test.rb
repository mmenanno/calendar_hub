# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class SyncServiceTest < ActiveSupport::TestCase
    include ModelBuilders
    include MochaHelpers
    include ICSTestHelpers

    setup do
      @source = calendar_sources(:provider)
      @source.credentials = { "http_basic_username" => "user", "http_basic_password" => "secret" }
      @source.save!
      @source.calendar_events.destroy_all
    end

    test "upserts fetched events and syncs with apple" do
      fetched_events = [
        build_ics_event(
          uid: "prov-999",
          summary: "Therapy",
          description: "Routine",
          location: "Studio",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          time_zone: @source.time_zone,
          raw_properties: { provider_data: { practitioner: "Dr. Smith" } },
        ),
      ]

      mock_ingestion_adapter(@source, events: fetched_events)
      apple_client = mock_apple_client
      apple_client.expects(:upsert_event).once
      apple_client.expects(:delete_event).never

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      event = @source.calendar_events.find_by(external_id: "prov-999")

      assert_predicate(event, :present?)
      refute_nil(event.reload.synced_at)
      assert_equal(32, @source.reload.sync_token.length)
    end

    test "broadcasts a single events refresh after sync" do
      fetched_events = [
        build_ics_event(uid: "refresh-1", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00")),
        build_ics_event(uid: "refresh-2", starts_at: Time.zone.parse("2025-09-24 12:00"), ends_at: Time.zone.parse("2025-09-24 13:00")),
      ]
      mock_ingestion_adapter(@source, events: fetched_events)
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event)

      Turbo::StreamsChannel.expects(:broadcast_refresh_later_to).with("calendar_events").once
      Turbo::StreamsChannel.expects(:broadcast_replace_later_to).never

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
    end

    test "persists feed cache headers only after a successful sync" do
      stub_request(:get, @source.ingestion_url)
        .to_return(status: 200, body: file_fixture("provider.ics").read, headers: { "ETag" => '"after-success"' })
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event).raises(ActiveRecord::StatementTimeout, "database is locked")
      apple_client.stubs(:delete_event)
      ::CalendarHub::Shared::AppleEventSyncer.any_instance.stubs(:sync_events_batch).raises(ActiveRecord::StatementTimeout, "database is locked")

      assert_raises(ActiveRecord::StatementTimeout) do
        ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
      end

      assert_nil(@source.reload.settings["etag"])

      ::CalendarHub::Shared::AppleEventSyncer.any_instance.unstub(:sync_events_batch)
      apple_client.stubs(:upsert_event)
      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call

      assert_equal('"after-success"', @source.reload.settings["etag"])
    end

    test "cancels and deletes missing events" do
      existing = build_event(
        calendar_source: @source,
        external_id: "legacy",
        title: "Legacy",
        **standard_event_times(Date.parse("2025-09-25")),
        status: :confirmed,
        last_synced_to_calendar: "Old Calendar",
      )
      keep = build_ics_event(uid: "still-there", starts_at: Time.zone.parse("2025-09-26 10:00"), ends_at: Time.zone.parse("2025-09-26 11:00"))

      mock_ingestion_adapter(@source, events: [keep])
      apple_client = mock_apple_client
      apple_client.expects(:upsert_event).once
      # Deleted from the calendar it was last pushed to, not the source default.
      apple_client.expects(:delete_event).with(calendar_identifier: "Old Calendar", uid: regexp_matches(/^ch-\d+-legacy$/)).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call

      assert_predicate(existing.reload, :cancelled?)
      assert_nil(existing.last_synced_to_calendar)
    end

    test "refuses to delete everything when the feed is empty" do
      existing = build_event(calendar_source: @source, external_id: "keep-me", last_synced_to_calendar: "personal")
      mock_ingestion_adapter(@source, events: [])
      apple_client = mock_apple_client
      apple_client.expects(:delete_event).never

      error = assert_raises(::CalendarHub::Ingestion::Error) do
        ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
      end

      assert_match(/Feed returned no events but 1 events/, error.message)
      assert_predicate(existing.reload, :confirmed?)
    end

    test "force sync removes events when the feed is really empty" do
      existing = build_event(calendar_source: @source, external_id: "gone", last_synced_to_calendar: "personal")
      mock_ingestion_adapter(@source, events: [])
      apple_client = mock_apple_client
      apple_client.expects(:delete_event).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, force: true).call

      assert_predicate(existing.reload, :cancelled?)
    end

    test "on 304 Not Modified pushes pending events without cancelling any" do
      # Create an existing event that should NOT be cancelled
      existing = @source.calendar_events.create!(
        external_id: "existing-event",
        title: "Existing Event",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :confirmed,
        data: {},
      )

      # Adapter returns nil to signal "no change" (HTTP 304)
      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(nil)
      apple_client = mock("apple_client")
      # Never pushed yet, so it is pending even though the feed is unchanged.
      apple_client.expects(:upsert_event).once
      apple_client.expects(:delete_event).never

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      result = service.call

      assert_equal([], result)
      # The existing event should still be confirmed (not cancelled)
      assert_predicate(existing.reload, :confirmed?)
    end

    test "raises error when no ingestion adapter" do
      service = ::CalendarHub::Sync::SyncService.new(source: @source, adapter: nil)
      # Force the adapter to be nil after initialization
      service.instance_variable_set(:@adapter, nil)

      error = assert_raises(::CalendarHub::Ingestion::Error) do
        service.call
      end

      assert_match(/No ingestion adapter configured/, error.message)
    end

    test "one invalid event does not prevent the others from being saved" do
      good_event = build_ics_event(
        uid: "good-event",
        summary: "Good Event",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        time_zone: @source.time_zone,
      )
      bad_event = build_ics_event(
        uid: "bad-event",
        summary: "Bad Event",
        starts_at: Time.zone.parse("2025-09-24 12:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"), # ends before it starts
        time_zone: @source.time_zone,
      )
      observer = ::CalendarHub::Shared::NullObserver.new
      observer.expects(:upsert_error).with { |event, error| event.external_id == "bad-event" && error.is_a?(ActiveRecord::RecordInvalid) }

      service = ::CalendarHub::Sync::SyncService.new(source: @source, observer: observer)
      result = service.send(:upsert_events, [good_event, bad_event])

      assert_equal(["good-event"], result.map(&:external_id))
      assert_predicate(@source.calendar_events.find_by(external_id: "good-event"), :present?)
      assert_nil(@source.calendar_events.find_by(external_id: "bad-event"))
    end

    test "upsert_events persists all events when all saves succeed" do
      events = [
        build_ics_event(
          uid: "event-1",
          summary: "Event 1",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          time_zone: @source.time_zone,
        ),
        build_ics_event(
          uid: "event-2",
          summary: "Event 2",
          starts_at: Time.zone.parse("2025-09-24 12:00"),
          ends_at: Time.zone.parse("2025-09-24 13:00"),
          time_zone: @source.time_zone,
        ),
      ]

      service = ::CalendarHub::Sync::SyncService.new(source: @source)
      result = service.send(:upsert_events, events)

      assert_equal(2, result.size)
      assert_predicate(@source.calendar_events.find_by(external_id: "event-1"), :present?)
      assert_predicate(@source.calendar_events.find_by(external_id: "event-2"), :present?)
    end

    test "raises error when calendar identifier is blank" do
      @source.calendar_identifier = ""
      @source.save(validate: false) # Skip validation to test the service logic

      service = ::CalendarHub::Sync::SyncService.new(source: @source)

      error = assert_raises(ArgumentError) do
        service.call
      end

      assert_match(/Calendar identifier is required/, error.message)
    end

    test "handles upsert errors gracefully" do
      fetched_events = [
        build_ics_event(
          uid: "error-event",
          summary: "Error Event",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          time_zone: @source.time_zone,
        ),
      ]

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).raises(StandardError, "Network error")
      apple_client.expects(:delete_event).never

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      event = @source.calendar_events.find_by(external_id: "error-event")

      assert_predicate(event, :present?)
      assert_nil(event.synced_at) # Should not be marked as synced due to error
    end

    test "handles cancel errors gracefully" do
      existing = @source.calendar_events.create!(
        external_id: "error-cancel",
        title: "Error Cancel",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :confirmed,
        data: {},
        last_synced_to_calendar: "personal",
      )

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).never
      apple_client.expects(:delete_event).raises(StandardError, "Delete error")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, force: true)
      service.call

      # Not marked cancelled: the next sync retries the delete.
      refute_predicate(existing.reload, :cancelled?)
      assert_equal("personal", existing.last_synced_to_calendar)
    end

    test "retries deletes of cancelled events still present in iCloud" do
      stranded = @source.calendar_events.create!(
        external_id: "stranded",
        title: "Stranded",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :cancelled,
        last_synced_to_calendar: "Work",
      )
      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(nil)
      apple_client = mock("apple_client")
      apple_client.expects(:delete_event).with(calendar_identifier: "Work", uid: regexp_matches(/stranded$/)).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call

      assert_nil(stranded.reload.last_synced_to_calendar)
    end

    test "deletes sync_exempt events" do
      fetched_events = [
        ::CalendarHub::ICS::Event.new(
          uid: "exempt-event",
          summary: "Exempt Event",
          description: "",
          location: "",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        ),
      ]

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:delete_event).with(calendar_identifier: any_parameters, uid: regexp_matches(/^ch-\d+-exempt-event$/)).once
      apple_client.expects(:upsert_event).never

      @source.calendar_events.create!(
        external_id: "exempt-event",
        title: "Exempt Event",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        last_synced_to_calendar: "personal",
        sync_exempt: true,
      )
      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)

      service.call

      event = @source.calendar_events.find_by(external_id: "exempt-event")

      assert_predicate(event, :present?)
      assert_predicate(event, :sync_exempt?)
    end

    test "deletes cancelled events" do
      fetched_events = [
        ::CalendarHub::ICS::Event.new(
          uid: "cancelled-event",
          summary: "Cancelled Event",
          description: "",
          location: "",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "cancelled",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        ),
      ]

      @source.calendar_events.create!(
        external_id: "cancelled-event",
        title: "Cancelled Event",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        last_synced_to_calendar: "personal",
      )
      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:delete_event).with(calendar_identifier: any_parameters, uid: regexp_matches(/^ch-\d+-cancelled-event$/)).once
      apple_client.expects(:upsert_event).never

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      event = @source.calendar_events.find_by(external_id: "cancelled-event")

      assert_predicate(event, :present?)
      assert_predicate(event, :cancelled?)
    end

    test "skips already cancelled events in cancel_missing_events" do
      existing = @source.calendar_events.create!(
        external_id: "already-cancelled",
        title: "Already Cancelled",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :cancelled,
        data: {},
      )

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).never
      apple_client.expects(:delete_event).never

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      assert_predicate(existing.reload, :cancelled?)
    end

    test "uses custom observer when provided" do
      observer = mock("observer")
      observer.expects(:start).with(total: 0)
      observer.expects(:finish).with(status: :success)

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, observer: observer)
      service.call
    end

    test "uses null observer by default" do
      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)

      assert_instance_of(::CalendarHub::Shared::NullObserver, service.observer)

      service.call

      @source.reload

      refute_nil(@source.last_synced_at)
    end

    test "calls observer methods during sync" do
      fetched_events = [
        ::CalendarHub::ICS::Event.new(
          uid: "observer-event",
          summary: "Observer Event",
          description: "",
          location: "",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        ),
      ]

      observer = mock("observer")
      observer.expects(:start).with(total: 1)
      observer.expects(:upsert_success).once
      observer.expects(:finish).with(status: :success)

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).once

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, observer: observer)
      service.call
    end

    test "calls observer delete_success for cancelled events" do
      @source.calendar_events.create!(
        external_id: "observer-cancel",
        title: "Observer Cancel",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :confirmed,
        data: {},
        last_synced_to_calendar: "personal",
      )

      observer = mock("observer")
      observer.expects(:start).with(total: 0)
      observer.expects(:delete_success).once
      observer.expects(:finish).with(status: :success)

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:delete_event).once

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, observer: observer, force: true)
      service.call
    end

    test "calls observer error methods when sync fails" do
      fetched_events = [
        ::CalendarHub::ICS::Event.new(
          uid: "observer-error",
          summary: "Observer Error",
          description: "",
          location: "",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        ),
      ]

      observer = mock("observer")
      observer.expects(:start).with(total: 1)
      observer.expects(:upsert_error).once
      observer.expects(:finish).with(status: :success)

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).raises(StandardError, "Sync error")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, observer: observer)
      service.call
    end

    test "generates sync token" do
      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      @source.reload

      assert_equal(32, @source.sync_token.length)
      refute_nil(@source.last_synced_at)
    end

    test "composite uid format is ch-<source>-<external_id>" do
      event = @source.calendar_events.create!(
        external_id: "test-uid",
        title: "Test Event",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        status: :confirmed,
        data: {},
      )

      result = ::CalendarHub::Shared::UidGenerator.composite_uid_for(event)

      assert_equal("ch-#{@source.id}-test-uid", result)
    end

    test "upsert_events resolves source time_zone once for the batch" do
      fetched_events = [
        build_ics_event(
          uid: "tz-event-1",
          summary: "TZ Event 1",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          time_zone: @source.time_zone,
        ),
        build_ics_event(
          uid: "tz-event-2",
          summary: "TZ Event 2",
          starts_at: Time.zone.parse("2025-09-24 12:00"),
          ends_at: Time.zone.parse("2025-09-24 13:00"),
          time_zone: @source.time_zone,
        ),
      ]

      mock_ingestion_adapter(@source, events: fetched_events)
      apple_client = mock_apple_client
      apple_client.expects(:upsert_event).twice

      # source.time_zone should be called at most twice (once cached in local
      # var during upsert, and once during generate_change_hash in mark_synced!),
      # NOT once per event.
      @source.expects(:time_zone).returns("America/Toronto").at_most(2)

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      event1 = @source.calendar_events.find_by(external_id: "tz-event-1")
      event2 = @source.calendar_events.find_by(external_id: "tz-event-2")

      assert_equal("America/Toronto", event1.time_zone)
      assert_equal("America/Toronto", event2.time_zone)
    end

    test "an unchanged feed does not re-push events, bump source_updated_at or write audits" do
      first = build_ics_event(uid: "stable", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"), raw_properties: { "x-note" => "a" })
      again = build_ics_event(uid: "stable", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"), raw_properties: { "x-note" => "a" })
      adapter = mock("adapter")
      adapter.stubs(:fetch_events).returns([first]).then.returns([again])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, adapter: adapter).call
      event = @source.calendar_events.find_by(external_id: "stable")
      source_updated_at = event.source_updated_at

      assert_no_difference(-> { CalendarEventAudit.count }) do
        ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: apple_client, adapter: adapter).call
      end
      assert_equal(source_updated_at, event.reload.source_updated_at)
    end

    test "changed content bumps source_updated_at and is pushed again" do
      original = build_ics_event(uid: "changing", summary: "Before", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      changed = build_ics_event(uid: "changing", summary: "After", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      adapter = mock("adapter")
      adapter.stubs(:fetch_events).returns([original]).then.returns([changed])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).twice

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, adapter: adapter).call
      travel(1.minute) do
        ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: apple_client, adapter: adapter).call
      end

      event = @source.calendar_events.find_by(external_id: "changing")

      assert_equal("After", event.title)
      assert_operator(event.synced_at, :>=, event.source_updated_at)
    end

    test "stores data with string keys only" do
      fetched = build_ics_event(uid: "keys", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"), raw_properties: { "x-client" => "Jane" })
      @source.calendar_events.create!(
        external_id: "keys",
        title: "Old",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        data: { "uid" => "keys", "dtstart_params" => { "TZID" => "UTC" }, "provider_data" => { "a" => 1 } },
      )
      mock_ingestion_adapter(@source, events: [fetched])
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event)

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call

      data = @source.calendar_events.find_by(external_id: "keys").data

      assert_equal({ "provider_data" => { "a" => 1 }, "x-client" => "Jane" }, data)
    end

    test "matches stored events when the feed UID has surrounding whitespace" do
      @source.calendar_events.create!(external_id: "padded", title: "Padded", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      fetched = build_ics_event(uid: " padded\r\n", summary: "Padded", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      mock_ingestion_adapter(@source, events: [fetched])
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event)

      assert_no_difference(-> { @source.calendar_events.count }) do
        ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
      end
    end

    test "persists filter rule exclusions and keeps a manual include across syncs" do
      FilterRule.create!(pattern: "Private", field_name: "title", match_type: "contains", active: true, calendar_source: @source)
      fetched = build_ics_event(uid: "private-1", summary: "Private thing", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      mock_ingestion_adapter(@source, events: [fetched])
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event)

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
      event = @source.calendar_events.find_by(external_id: "private-1")

      assert_predicate(event, :excluded_by_rule?)
      assert_predicate(event, :sync_exempt?)

      event.toggle_sync_exempt!
      ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: apple_client).call

      refute_predicate(event.reload, :sync_exempt?)
      assert_equal("include", event.manual_sync_override)
    end

    test "keeps past occurrences of a series that is still in the feed" do
      old_occurrence = @source.calendar_events.create!(
        external_id: "series::20200101T100000Z",
        title: "Series",
        starts_at: Time.utc(2020, 1, 1, 10),
        ends_at: Time.utc(2020, 1, 1, 11),
        last_synced_to_calendar: "personal",
      )
      current = build_ics_event(uid: "series::#{1.day.from_now.utc.strftime("%Y%m%dT100000Z")}", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
      adapter = mock("adapter")
      adapter.stubs(:fetch_events).returns([current])
      adapter.stubs(:recurrence_window_start).returns(30.days.ago)
      apple_client = mock_apple_client
      apple_client.stubs(:upsert_event)
      apple_client.expects(:delete_event).never

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, adapter: adapter).call

      refute_predicate(old_occurrence.reload, :cancelled?)
    end

    test "closes the Apple client connections after the sync" do
      mock_ingestion_adapter(@source, events: [])
      apple_client = mock_apple_client
      apple_client.expects(:finish).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call
    end

    test "force sync fetches unconditionally and re-pushes unchanged events" do
      fetched = build_ics_event(uid: "forced", starts_at: Time.zone.parse("2025-09-24 10:00"), ends_at: Time.zone.parse("2025-09-24 11:00"))
      adapter = mock("adapter")
      adapter.expects(:fetch_events).with(conditional: false).twice.returns([fetched])
      apple_client = mock_apple_client
      apple_client.expects(:upsert_event).twice

      2.times { ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: apple_client, adapter: adapter, force: true).call }
    end

    test "uses conditional requests once the configuration is unchanged and the last sync succeeded" do
      @source.mark_synced!(token: "t")
      adapter = mock("adapter")
      adapter.expects(:fetch_events).with(conditional: true).returns(nil)

      ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: mock_apple_client, adapter: adapter).call
    end

    test "fetches unconditionally after a failed sync" do
      @source.mark_synced!(token: "t")
      @source.update!(consecutive_sync_failures: 2)
      adapter = mock("adapter")
      adapter.expects(:fetch_events).with(conditional: false).returns([])

      ::CalendarHub::Sync::SyncService.new(source: @source.reload, apple_client: mock_apple_client, adapter: adapter).call
    end

    private

    def stub_adapter(_fetched_events); end
  end
end
