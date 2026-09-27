# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Sync
    class FilterSyncServiceTest < ActiveSupport::TestCase
      def setup
        @source = calendar_sources(:provider)
        @service = ::CalendarHub::Sync::FilterSyncService.new(source: @source)
      end

      test "sync_filter_rules returns zeros when source is blank" do
        service = ::CalendarHub::Sync::FilterSyncService.new(source: nil)
        result = service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 0 }, result)
      end

      test "sync_filter_rules returns counts when no changes needed" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(0)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(0)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 0 }, result)
      end

      test "sync_filter_rules triggers apple sync when filtered_count > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(5)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(0)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 5, re_included: 0 }, result)
      end

      test "sync_filter_rules triggers apple sync when re_included_count > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(0)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(3)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 0, re_included: 3 }, result)
      end

      test "sync_filter_rules triggers apple sync when both counts > 0" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).returns(2)
        ::CalendarHub::EventFilter.expects(:apply_reverse_filtering).with(@source).returns(1)
        @source.expects(:schedule_sync).with(force: true)

        result = @service.sync_filter_rules

        assert_equal({ filtered: 2, re_included: 1 }, result)
      end

      test "sync_filter_rules does not sleep on SQLite3::BusyException and lets it propagate" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).raises(SQLite3::BusyException.new("database is locked"))

        # Ensure sleep is never called on the service
        @service.expects(:sleep).never

        assert_raises(SQLite3::BusyException) do
          @service.sync_filter_rules
        end
      end

      test "sync_filter_rules does not sleep on ActiveRecord::StatementTimeout and lets it propagate" do
        ::CalendarHub::EventFilter.expects(:apply_backwards_filtering).with(@source).raises(ActiveRecord::StatementTimeout.new("database is locked"))

        @service.expects(:sleep).never

        assert_raises(ActiveRecord::StatementTimeout) do
          @service.sync_filter_rules
        end
      end

      test "trigger_apple_sync calls schedule_sync with force: true" do
        @source.expects(:schedule_sync).with(force: true)
        @service.send(:trigger_apple_sync)
      end
    end
  end
end
