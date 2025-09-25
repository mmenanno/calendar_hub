# frozen_string_literal: true

module CalendarHub
  module ICS
    Event = Data.define(:uid, :summary, :description, :location, :starts_at, :ends_at, :status, :time_zone, :raw_properties)
  end
end
