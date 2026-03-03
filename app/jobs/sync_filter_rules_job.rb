# frozen_string_literal: true

class SyncFilterRulesJob < ApplicationJob
  retry_on ActiveRecord::StatementTimeout, wait: :exponentially_longer, attempts: 5
  retry_on SQLite3::BusyException, wait: :exponentially_longer, attempts: 5
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 5

  def perform(filter_rule_id = nil, calendar_source_id: nil)
    source_id = calendar_source_id

    if filter_rule_id
      filter_rule = FilterRule.find(filter_rule_id)
      source_id = filter_rule.calendar_source_id
    end

    with_error_tracking(context: "sync filter rules") do
      if source_id
        source = CalendarSource.find(source_id)
        CalendarHub::Sync::FilterSyncService.new(source: source).sync_filter_rules
      else
        # Fan-out: enqueue one job per active source so they can run
        # concurrently across available workers instead of sequentially.
        CalendarSource.active.ids.each do |id|
          self.class.perform_later(calendar_source_id: id)
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("[SyncFilterRulesJob] Record not found, skipping sync")
  end
end
