# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class SyncServiceTest < ActiveSupport::TestCase
    setup do
      @source = calendar_sources(:jane_app)
      @source.credentials = { "http_basic_username" => "user", "http_basic_password" => "secret" }
      @source.save!
      @source.calendar_events.destroy_all
    end

    test "upserts fetched events and syncs with apple" do
      fetched_events = [
        CalendarHub::ICS::Event.new(
          uid: "jane-999",
          summary: "Therapy",
          description: "Routine",
          location: "Studio",
          starts_at: Time.zone.parse("2025-09-24 10:00"),
          ends_at: Time.zone.parse("2025-09-24 11:00"),
          status: "confirmed",
          time_zone: @source.time_zone,
          raw_properties: { provider_data: { practitioner: "Dr. Smith" } },
        ),
      ]

      CalendarHub::Ingestion::GenericIcsAdapter.any_instance.expects(:fetch_events).returns(fetched_events)
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).once
      apple_client.expects(:delete_event).never

      service = CalendarHub::SyncService.new(source: @source, apple_client: apple_client)
      service.call

      event = @source.calendar_events.find_by(external_id: "jane-999")

      assert_predicate event, :present?
      refute_nil event.reload.synced_at
      assert_equal 32, @source.reload.sync_token.length
    end

    test "cancels and deletes missing events" do
      existing = @source.calendar_events.create!(
        external_id: "legacy",
        title: "Legacy",
        description: "",
        location: "",
        starts_at: Time.zone.parse("2025-09-25 09:00"),
        ends_at: Time.zone.parse("2025-09-25 10:00"),
        status: :confirmed,
        data: {},
      )

      CalendarHub::Ingestion::GenericIcsAdapter.any_instance.expects(:fetch_events).returns([])
      apple_client = mock("apple_client")
      apple_client.expects(:upsert_event).never
      apple_client.expects(:delete_event).with(calendar_identifier: any_parameters, uid: regexp_matches(/^ch-\d+-legacy$/)).once

      CalendarHub::SyncService.new(source: @source, apple_client: apple_client).call

      assert_predicate existing.reload, :cancelled?
    end

    private

    def stub_adapter(_fetched_events); end
  end
end
