# frozen_string_literal: true

module CalendarHub
  class EventFilter
    attr_reader :calendar_source, :rules

    # Initialize with a calendar source to preload filter rules once.
    # This avoids N+1 queries when filtering a batch of events.
    def initialize(calendar_source)
      @calendar_source = calendar_source
      @rules = FilterRule.active.where(calendar_source_id: [nil, calendar_source&.id]).to_a
    end

    def should_filter?(event)
      return false if event.blank?

      rules.any? { |rule| rule.matches?(event) }
    end

    class << self
      def should_filter?(event)
        return false if event.blank?

        source = event.calendar_source
        new(source).should_filter?(event)
      end

      def apply_filters(events)
        return events if events.blank?

        # Group events by calendar_source_id to minimize filter instances
        events_by_source = events.group_by { |e| e.respond_to?(:calendar_source_id) ? e.calendar_source_id : nil }

        events_by_source.each do |_source_id, source_events|
          representative = source_events.first
          source = representative.respond_to?(:calendar_source) ? representative.calendar_source : nil
          filter = new(source)

          source_events.each do |event|
            event.sync_exempt = true if filter.should_filter?(event)
          end
        end

        events
      end

      def apply_backwards_filtering(source = nil)
        scope = CalendarEvent.where(sync_exempt: false)
        scope = scope.where(calendar_source: source) if source

        filter = new(source)
        filtered_count = 0

        scope.in_batches(of: 1000) do |batch|
          ActiveRecord::Base.transaction do
            batch.each do |event|
              if filter.should_filter?(event)
                event.update!(sync_exempt: true)
                filtered_count += 1
              end
            end
          end
        end

        filtered_count
      end

      def find_re_includable_events(source = nil)
        scope = CalendarEvent.where(sync_exempt: true)
        scope = scope.where(calendar_source: source) if source

        filter = new(source)
        re_includable = []

        scope.find_each do |event|
          unless filter.should_filter?(event)
            re_includable << event
          end
        end

        re_includable
      end

      def apply_reverse_filtering(source = nil)
        scope = CalendarEvent.where(sync_exempt: true)
        scope = scope.where(calendar_source: source) if source

        filter = new(source)
        re_included_count = 0

        scope.in_batches(of: 1000) do |batch|
          ActiveRecord::Base.transaction do
            batch.each do |event|
              unless filter.should_filter?(event)
                event.update!(sync_exempt: false)
                re_included_count += 1
              end
            end
          end
        end

        re_included_count
      end
    end
  end
end
