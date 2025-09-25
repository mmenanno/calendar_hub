# frozen_string_literal: true

module CalendarHub
  module Translators
    class << self
      def for(_provider)
        Translators::EventTranslator
      end

      def register(*); end
    end
  end
end
