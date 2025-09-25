# frozen_string_literal: true

if defined?(SolidQueue) && Rails.env.production?
  Rails.application.configure do
    config.solid_queue.recurring_tasks = {
      auto_sync_scheduler: {
        class: "AutoSyncSchedulerJob",
        schedule: "every 5 minutes",
        description: "Schedule automatic sync jobs for calendar sources",
      },
    }
  end
end
