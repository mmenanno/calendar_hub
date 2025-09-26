# frozen_string_literal: true

module CalendarHub
  class NameMapper
    class << self
      def apply(title, source: nil)
        return title if title.blank?

        rules = cached_active_mappings(source)
        rules.each do |rule|
          case rule.match_type
          when "equals"
            return rule.replacement if compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :equals)
          when "contains"
            return rule.replacement if compare?(title, rule.pattern, case_sensitive: rule.case_sensitive, mode: :contains)
          when "regex"
            begin
              flags = rule.case_sensitive ? nil : Regexp::IGNORECASE
              re = Regexp.new(rule.pattern, flags)
              return title.gsub(re, rule.replacement)
            rescue RegexpError
              next
            end
          end
        end

        title
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

      def cached_active_mappings(source)
        cache_key = "name_mapper/active_mappings/#{source&.id || "global"}"
        Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
          EventMapping.active.where(calendar_source_id: [nil, source&.id]).to_a
        end
      end
    end
  end
end
