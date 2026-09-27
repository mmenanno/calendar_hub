# frozen_string_literal: true

module CalendarHub
  # Evaluates filter rules. Rule decisions are persisted in
  # CalendarEvent#excluded_by_rule and never touch the manual override, so a
  # user's include/exclude choice survives rule changes and later syncs.
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

      # Sets excluded_by_rule (and the derived sync_exempt) in memory; the
      # caller persists the events.
      def apply_filters(events)
        return events if events.blank?

        # Group events by calendar_source_id to minimize filter instances
        events_by_source = events.group_by { |e| e.respond_to?(:calendar_source_id) ? e.calendar_source_id : nil }

        events_by_source.each_value do |source_events|
          representative = source_events.first
          source = representative.respond_to?(:calendar_source) ? representative.calendar_source : nil
          filter = new(source)

          source_events.each do |event|
            event.apply_rule_exclusion(filter.should_filter?(event))
          end
        end

        events
      end

      # Marks events newly matched by a rule. Returns the number of events
      # whose rule exclusion changed.
      def apply_backwards_filtering(source = nil)
        update_rule_exclusions(source, currently_excluded: false) { |filter, event| filter.should_filter?(event) }
      end

      # Clears the rule exclusion of events no rule matches any more.
      # Manually excluded events stay excluded.
      def apply_reverse_filtering(source = nil)
        update_rule_exclusions(source, currently_excluded: true) { |filter, event| !filter.should_filter?(event) }
      end

      def find_re_includable_events(source = nil)
        each_source_scope(source).flat_map do |filter, scope|
          scope.where(excluded_by_rule: true).to_a.reject { |event| filter.should_filter?(event) }
        end
      end

      private

      def update_rule_exclusions(source, currently_excluded:)
        changed = 0
        each_source_scope(source).each do |filter, scope|
          scope.where(excluded_by_rule: currently_excluded).in_batches(of: 1000) do |batch|
            ActiveRecord::Base.transaction do
              batch.each do |event|
                next unless yield(filter, event)

                event.update!(excluded_by_rule: !currently_excluded)
                changed += 1
              end
            end
          end
        end
        changed
      end

      # Yields [filter, events scope] per source so source-specific rules are
      # always evaluated together with global ones.
      def each_source_scope(source)
        sources = source ? [source] : CalendarSource.unscoped.where(id: CalendarEvent.distinct.select(:calendar_source_id)).to_a
        sources.map { |each_source| [new(each_source), CalendarEvent.where(calendar_source_id: each_source.id)] }
      end
    end
  end
end
