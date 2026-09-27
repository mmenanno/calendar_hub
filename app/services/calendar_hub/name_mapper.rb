# frozen_string_literal: true

module CalendarHub
  # Applies EventMapping rules (title rewrites and destination overrides).
  #
  # Syncs build one instance per run with NameMapper.for(source): mappings are
  # loaded once and regexes compiled once. The class-level helpers used by
  # views/controllers memoize instances per request/job via
  # ActiveSupport::CurrentAttributes (reset automatically between requests
  # and jobs, and explicitly whenever a mapping is committed).
  class NameMapper
    class Memo < ActiveSupport::CurrentAttributes
      attribute :mappers
    end

    attr_reader :mappings

    class << self
      def for(source)
        new(EventMapping.active.where(calendar_source_id: [nil, source&.id]).to_a)
      end

      def apply(title, source: nil)
        memoized(source).apply(title)
      end

      def matching_rule(title, source: nil)
        memoized(source).matching_rule(title)
      end

      def destination_for(title, source: nil)
        memoized(source).destination_for(title)
      end

      def reset_cache!
        Memo.mappers = nil
      end

      def compare?(text, pattern, case_sensitive:, mode:)
        a = text.to_s
        b = pattern.to_s
        unless case_sensitive
          a = a.downcase
          b = b.downcase
        end
        case mode
        when :equals
          a == b
        when :contains
          a.include?(b)
        else
          false
        end
      end

      private

      def memoized(source)
        Memo.mappers ||= {}
        Memo.mappers[source&.id || :global] ||= self.for(source)
      end
    end

    def initialize(mappings)
      @mappings = mappings
      @regexes = mappings.each_with_object({}.compare_by_identity) do |mapping, memo|
        memo[mapping] = SafeRegexp.compile(mapping.pattern, case_sensitive: mapping.case_sensitive) if mapping.match_type == "regex"
      end
    end

    def apply(title)
      return title if title.blank?

      mappings.each do |rule|
        next unless matches?(title, rule)
        return title if rule.replacement.blank?

        return SafeRegexp.gsub(@regexes[rule], title, rule.replacement) if rule.match_type == "regex"

        return rule.replacement
      end

      title
    end

    def matching_rule(title)
      return if title.blank?

      mappings.find { |rule| matches?(title, rule) }
    end

    def destination_for(title)
      matching_rule(title)&.target_calendar_identifier.presence
    end

    private

    def matches?(title, rule)
      case rule.match_type
      when "equals"
        self.class.compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :equals)
      when "contains"
        self.class.compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :contains)
      when "regex"
        SafeRegexp.match?(@regexes[rule], title)
      else
        false
      end
    end
  end
end
