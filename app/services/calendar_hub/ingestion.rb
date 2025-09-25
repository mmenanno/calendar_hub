# frozen_string_literal: true

require_relative "ingestion/generic_ics_adapter"

module CalendarHub
  module Ingestion
    Error = Class.new(StandardError)
  end
end
