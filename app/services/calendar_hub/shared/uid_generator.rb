# frozen_string_literal: true

module CalendarHub
  module Shared
    class UidGenerator
      class << self
        def composite_uid_for(event)
          "ch-#{event.calendar_source_id}-#{event.external_id}"
        end
      end
    end
  end
end
