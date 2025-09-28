# frozen_string_literal: true

class PurgeCalendarSourceJob < ApplicationJob
  def perform(source_id)
    with_error_tracking(context: "purge calendar_source_id=#{source_id}") do
      source = CalendarSource.unscoped.find_by(id: source_id)
      return unless source

      purge_service = CalendarHub::PurgeService.new(source)
      purge_service.call
    end
  end
end
