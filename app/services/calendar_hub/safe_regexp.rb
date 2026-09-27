# frozen_string_literal: true

module CalendarHub
  # Compiles and runs user-supplied patterns (filter rules, event mappings)
  # with a match timeout so a pathological regex cannot hang a sync.
  module SafeRegexp
    TIMEOUT = 1.0

    class << self
      # Returns nil for invalid patterns.
      def compile(pattern, case_sensitive:)
        Regexp.new(pattern.to_s, case_sensitive ? nil : Regexp::IGNORECASE, timeout: TIMEOUT)
      rescue RegexpError
        nil
      end

      # Timeouts are treated as a non-match.
      def match?(regex, text)
        return false if regex.nil?

        regex.match?(text.to_s)
      rescue Regexp::TimeoutError
        Rails.logger.warn("[SafeRegexp] Pattern #{regex.source.inspect} timed out; treating as no match")
        false
      end

      def gsub(regex, text, replacement)
        return text if regex.nil?

        text.gsub(regex, replacement)
      rescue Regexp::TimeoutError
        Rails.logger.warn("[SafeRegexp] Pattern #{regex.source.inspect} timed out; leaving title unchanged")
        text
      end
    end
  end
end
