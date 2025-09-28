# frozen_string_literal: true

class AutoSyncSchedulerJob < ApplicationJob
  def perform
    with_error_tracking(context: "auto sync scheduling") do
      scheduler = CalendarHub::AutoSyncScheduler.new
      scheduler.call
    end
  end
end
