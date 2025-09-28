# frozen_string_literal: true

require "test_helper"
require Rails.root.join("app/services/calendar_hub/sync_service")

module CalendarHub
  class NullObserverTest < ActiveSupport::TestCase
    def setup
      @observer = CalendarHub::NullObserver.new
      @event = calendar_events(:provider_consult)
      @error = StandardError.new("Test error")
    end

    test "start method accepts total parameter and returns nil" do
      result = @observer.start(total: 10)

      assert_nil(result)
    end

    test "start method works with no parameters" do
      result = @observer.start

      assert_nil(result)
    end

    test "upsert_success method accepts event and returns nil" do
      result = @observer.upsert_success(@event)

      assert_nil(result)
    end

    test "upsert_error method accepts event and error and returns nil" do
      result = @observer.upsert_error(@event, @error)

      assert_nil(result)
    end

    test "delete_success method accepts event and returns nil" do
      result = @observer.delete_success(@event)

      assert_nil(result)
    end

    test "delete_error method accepts event and error and returns nil" do
      result = @observer.delete_error(@event, @error)

      assert_nil(result)
    end

    test "finish method accepts status parameter and returns nil" do
      result = @observer.finish(status: :success)

      assert_nil(result)
    end

    test "finish method accepts status and message parameters and returns nil" do
      result = @observer.finish(status: :failed, message: "Sync failed")

      assert_nil(result)
    end

    test "finish method works with no parameters" do
      result = @observer.finish

      assert_nil(result)
    end

    test "all methods can be called without raising errors" do
      assert_nothing_raised do
        @observer.start(total: 5)
        @observer.upsert_success(@event)
        @observer.upsert_error(@event, @error)
        @observer.delete_success(@event)
        @observer.delete_error(@event, @error)
        @observer.finish(status: :success, message: "Complete")
      end
    end

    test "can be used as observer replacement" do
      observer = CalendarHub::NullObserver.new

      observer.start(total: 2)
      observer.upsert_success(@event)
      observer.delete_success(@event)
      observer.finish(status: :success)

      assert_instance_of(CalendarHub::NullObserver, observer)
    end
  end
end
