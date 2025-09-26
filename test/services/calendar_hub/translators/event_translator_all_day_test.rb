# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Translators
    class EventTranslatorAllDayTest < ActiveSupport::TestCase
      setup do
        @source = calendar_sources(:ics_feed)
        @translator = EventTranslator.new(@source)
      end

      test "includes all_day field for all-day event" do
        event = CalendarEvent.create!(
          calendar_source: @source,
          external_id: "all-day-translator-test",
          title: "All Day Event",
          starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
          ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
          time_zone: "UTC",
          all_day: true,
        )

        payload = @translator.call(event)

        assert(payload[:all_day])
        assert_equal("All Day Event", payload[:summary])
        assert_equal(event.starts_at, payload[:starts_at])
        assert_equal(event.ends_at, payload[:ends_at])
      end

      test "includes all_day field for timed event" do
        event = CalendarEvent.create!(
          calendar_source: @source,
          external_id: "timed-translator-test",
          title: "Timed Event",
          starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
          ends_at: Time.utc(2025, 9, 27, 15, 0, 0),
          time_zone: "UTC",
          all_day: false,
        )

        payload = @translator.call(event)

        refute(payload[:all_day])
        assert_equal("Timed Event", payload[:summary])
        assert_equal(event.starts_at, payload[:starts_at])
        assert_equal(event.ends_at, payload[:ends_at])
      end

      test "generates correct composite uid" do
        event = CalendarEvent.create!(
          calendar_source: @source,
          external_id: "uid-test-123",
          title: "UID Test",
          starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
          ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
          time_zone: "UTC",
          all_day: true,
        )

        payload = @translator.call(event)

        expected_uid = "ch-#{@source.id}-uid-test-123"

        assert_equal(expected_uid, payload[:uid])
      end
    end
  end
end
