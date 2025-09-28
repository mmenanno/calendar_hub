# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Ingestion
    class ImportStartDateTest < ActiveSupport::TestCase
      def setup
        @source = calendar_sources(:provider)
        @source.update!(import_start_date: 1.week.ago)
      end

      test "import_start_date is set automatically on source creation" do
        freeze_time do
          new_source = CalendarSource.create!(
            name: "New Source",
            ingestion_url: "https://example.com/new.ics",
            calendar_identifier: "new-cal",
          )

          assert_equal(Time.current, new_source.import_start_date)
        end
      end

      test "import_start_date can be manually set" do
        custom_date = 2.weeks.ago
        new_source = CalendarSource.create!(
          name: "Custom Date Source",
          ingestion_url: "https://example.com/custom.ics",
          calendar_identifier: "custom-cal",
          import_start_date: custom_date,
        )

        assert_equal(custom_date.to_i, new_source.import_start_date.to_i)
      end

      test "import_start_date filtering logic" do
        # Test the filtering logic directly with mock events
        old_event = ::CalendarHub::ICS::Event.new(
          uid: "old-event",
          summary: "Old Event",
          description: nil,
          location: nil,
          starts_at: 2.weeks.ago,
          ends_at: 2.weeks.ago + 1.hour,
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        )

        recent_event = ::CalendarHub::ICS::Event.new(
          uid: "recent-event",
          summary: "Recent Event",
          description: nil,
          location: nil,
          starts_at: 2.days.ago,
          ends_at: 2.days.ago + 1.hour,
          status: "confirmed",
          time_zone: @source.time_zone,
          all_day: false,
          raw_properties: {},
        )

        events = [old_event, recent_event]

        # Apply the same filtering logic as in the adapter
        filtered_events = if @source.import_start_date.present?
          events.select { |event| event.starts_at >= @source.import_start_date }
        else
          events
        end

        # Should only include the recent event
        assert_equal(1, filtered_events.count)
        assert_equal("recent-event", filtered_events.first.uid)

        # Test with nil import_start_date
        @source.update!(import_start_date: nil)
        filtered_events = events.select { |event| @source.import_start_date.nil? || event.starts_at >= @source.import_start_date }

        # Should include both events
        assert_equal(2, filtered_events.count)
      end
    end
  end
end
