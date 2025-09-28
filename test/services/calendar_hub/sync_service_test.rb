# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class SyncServiceTest < ActiveSupport::TestCase
    include ModelBuilders
    include MochaHelpers

    setup do
      @source = calendar_sources(:provider)
      @source.credentials = { "http_basic_username" => "user", "http_basic_password" => "secret" }
      @source.save!
      @source.calendar_events.destroy_all
    end

    test "upserts fetched events and syncs with apple" do
      fetched_events = [
        ::CalendarHub::ICS::Event.new(
          uid: "prov-999",
          summary: "Therapy",
          description: "Routine",
          location: "Studio",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
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

      assert_predicate event, :present?
      refute_nil event.reload.synced_at
      assert_equal 32, @source.reload.sync_token.length
    end

    test "cancels and deletes missing events" do
      existing = build_event(
        calendar_source: @source,
        external_id: "legacy",
        title: "Legacy",
        **standard_event_times(Date.parse("2025-09-25")),
        status: :confirmed,
      )

      mock_ingestion_adapter(@source, events: [])
      apple_client = mock_apple_client
      apple_client.expects(:upsert_event).never
      apple_client.expects(:delete_event).with(calendar_identifier: any_parameters, uid: regexp_matches(/^ch-\d+-legacy$/)).once

      ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client).call

      assert_predicate existing.reload, :cancelled?
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
        ::CalendarHub::ICS::Event.new(
          uid: "error-event",
          summary: "Error Event",
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
      )

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).never
      apple_client.expects(:delete_event).raises(StandardError, "Delete error")

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      assert_predicate(existing.reload, :cancelled?)
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

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client)

      # Mock the event to be sync_exempt
      CalendarEvent.any_instance.stubs(:sync_exempt?).returns(true)

      service.call

      event = @source.calendar_events.find_by(external_id: "exempt-event")

      assert_predicate(event, :present?)
    ensure
      CalendarEvent.any_instance.unstub(:sync_exempt?)
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

      # Should not raise any errors when calling observer methods
      assert_nothing_raised do
        service.call
      end
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
      )

      observer = mock("observer")
      observer.expects(:start).with(total: 0)
      observer.expects(:delete_success).once
      observer.expects(:finish).with(status: :success)

      ::CalendarHub::Ingestion::GenericICSAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:delete_event).once

      service = ::CalendarHub::Sync::SyncService.new(source: @source, apple_client: apple_client, observer: observer)
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

    test "event_url_for handles routing errors" do
      service = ::CalendarHub::Sync::SyncService.new(source: @source)

      # Mock the url_helpers to raise an error
      Rails.application.routes.url_helpers.stubs(:calendar_event_url).raises(StandardError, "Routing error")

      event = @source.calendar_events.create!(
        external_id: "url-error",
        title: "URL Error",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-24 10:00"),
        ends_at: Time.zone.parse("2025-09-24 11:00"),
        status: :confirmed,
        data: {},
      )

      result = service.send(:event_url_for, event)

      assert_nil(result)
    ensure
      Rails.application.routes.url_helpers.unstub(:calendar_event_url)
    end

    test "composite_uid_for generates correct format" do
      service = ::CalendarHub::Sync::SyncService.new(source: @source)

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

      result = service.send(:composite_uid_for, event)

      assert_equal("ch-#{@source.id}-test-uid", result)
    end

    private

    def stub_adapter(_fetched_events); end
  end
end
