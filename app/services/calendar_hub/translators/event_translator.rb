# frozen_string_literal: true

module CalendarHub
  module Translators
    class EventTranslator
      attr_reader :source

      def initialize(source)
        @source = source
      end

      def call(event)
        base_payload(event)
      end

      protected

      def base_payload(event)
        {
          uid: "ch-#{event.calendar_source_id}-#{event.external_id}",
          summary: event.title,
          description: event.description,
          location: event.location,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          status: event.status,
          all_day: event.all_day?,
          transparency: "opaque",
        }
      end
    end
  end
end
