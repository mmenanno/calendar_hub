# frozen_string_literal: true

require "test_helper"

class SyncServiceNotificationsTest < ActiveSupport::TestCase
  class FakeAdapter
    def initialize(_source); end

    # 304 Not Modified
    def fetch_events(conditional: true) # rubocop:disable Lint/UnusedMethodArgument
      nil
    end
  end

  test "emits calendar_hub.sync notification with payload, including 304 syncs" do
    source = calendar_sources(:ics_feed)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("calendar_hub.sync") do |name, _start, _finish, _id, payload|
      events << [name, payload]
    end

    apple_client = mock("apple_client")
    apple_client.stubs(:upsert_event)
    service = CalendarHub::Sync::SyncService.new(
      source: source,
      apple_client: apple_client,
      observer: CalendarHub::Shared::NullObserver.new,
      adapter: FakeAdapter.new(source),
    )
    service.call

    assert_equal(1, events.size)
    name, payload = events.first

    assert_equal("calendar_hub.sync", name)
    assert_equal(source.id, payload[:source_id])
    assert_equal(0, payload[:fetched])
    assert_equal(0, payload[:errors])
    assert(payload[:not_modified])
    assert_kind_of(Integer, payload[:duration_ms])
  ensure
    # Only remove this test's subscriber; the metrics initializer's must stay.
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "persists a sync metric with the per-event error count" do
    source = calendar_sources(:ics_feed)
    source.calendar_events.where.not(status: "cancelled").update_all(last_synced_to_calendar: "shared")
    apple_client = mock("apple_client")
    apple_client.stubs(:upsert_event).raises(StandardError, "CalDAV PUT failed")
    apple_client.stubs(:delete_event)

    assert_difference(-> { SyncMetric.where(calendar_source: source).count }, 1) do
      CalendarHub::Sync::SyncService.new(source: source, apple_client: apple_client, adapter: FakeAdapter.new(source)).call
    end

    metric = SyncMetric.where(calendar_source: source).order(:id).last

    assert_operator(metric.errors_count, :>, 0)
  end
end
