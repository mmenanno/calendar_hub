# frozen_string_literal: true

module CalendarHub
  class EventFilter
    class << self
      def should_filter?(event)
        return false if event.blank?

        source = event.calendar_source
        rules = FilterRule.active.where(calendar_source_id: [nil, source&.id])

        rules.any? { |rule| rule.matches?(event) }
      end

      def apply_filters(events)
        return events if events.blank?

        events.each do |event|
          if should_filter?(event)
            event.sync_exempt = true
          end
        end

        events
      end

      def apply_backwards_filtering(source = nil)
        scope = CalendarEvent.where(sync_exempt: false)
        scope = scope.where(calendar_source: source) if source

        filtered_count = 0

        scope.find_each do |event|
          if should_filter?(event)
            event.update!(sync_exempt: true)
            filtered_count += 1
          end
        end

        filtered_count
      end

      def find_re_includable_events(source = nil)
        scope = CalendarEvent.where(sync_exempt: true)
        scope = scope.where(calendar_source: source) if source

        re_includable = []

        scope.find_each do |event|
          unless should_filter?(event)
            re_includable << event
          end
        end

        re_includable
      end

      def apply_reverse_filtering(source = nil)
        re_includable = find_re_includable_events(source)

        re_includable.each do |event|
          event.update!(sync_exempt: false)
        end

        re_includable.count
      end
    end
  end
end
