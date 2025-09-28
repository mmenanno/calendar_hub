# frozen_string_literal: true

require "test_helper"

class SyncServiceNotificationsTest < ActiveSupport::TestCase
  class FakeAdapter
    def initialize(_source); end

    def fetch_events
      []
    end
  end

  test "emits calendar_hub.sync notification with payload" do
    source = calendar_sources(:ics_feed)
    events = []
    ActiveSupport::Notifications.subscribe("calendar_hub.sync") do |name, _start, _finish, _id, payload|
      events << [name, payload]
    end

    service = CalendarHub::Sync::SyncService.new(source: source, observer: CalendarHub::Shared::NullObserver.new, adapter: FakeAdapter.new(source))
    service.call

    assert_equal(1, events.size)
    name, payload = events.first

    assert_equal("calendar_hub.sync", name)
    assert_equal(source.id, payload[:source_id])
    assert_equal(0, payload[:fetched])
    assert_kind_of(Integer, payload[:duration_ms])
  ensure
    ActiveSupport::Notifications.unsubscribe("calendar_hub.sync")
  end
end
