# frozen_string_literal: true

module CalendarHub
  class NameMapper
    class << self
      def apply(title, source: nil)
        return title if title.blank?

        rules = cached_active_mappings(source)
        rules.each do |rule|
          if matches?(title, rule)
            return title if rule.replacement.blank?

            case rule.match_type
            when "regex"
              begin
                flags = rule.case_sensitive ? nil : Regexp::IGNORECASE
                re = Regexp.new(rule.pattern, flags)
                return title.gsub(re, rule.replacement)
              rescue RegexpError
                next
              end
            else
              return rule.replacement
            end
          end
        end

        title
      end

      def matching_rule(title, source: nil)
        return nil if title.blank?

        rules = cached_active_mappings(source)
        rules.find { |rule| matches?(title, rule) }
      end

      def destination_for(title, source: nil)
        rule = matching_rule(title, source: source)
        rule&.target_calendar_identifier.presence
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

      def matches?(title, rule)
        case rule.match_type
        when "equals"
          compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :equals)
        when "contains"
          compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :contains)
        when "regex"
          begin
            flags = rule.case_sensitive ? nil : Regexp::IGNORECASE
            re = Regexp.new(rule.pattern, flags)
            !!(title =~ re)
          rescue RegexpError
            false
          end
        else
          false
        end
      end

      def cached_active_mappings(source)
        cache_key = "name_mapper/active_mappings/#{source&.id || "global"}"
        Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
          EventMapping.active.where(calendar_source_id: [nil, source&.id]).to_a
        end
      end
    end
  end
end
