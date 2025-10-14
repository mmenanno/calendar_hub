# frozen_string_literal: true

class SyncFilterRulesJob < ApplicationJob
  retry_on ActiveRecord::StatementTimeout, wait: :exponentially_longer, attempts: 3
  retry_on SQLite3::BusyException, wait: :exponentially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3

  def perform(filter_rule_id)
    filter_rule = FilterRule.find(filter_rule_id)

    with_error_tracking(context: "sync filter rules for filter_rule_id=#{filter_rule_id}") do
      if filter_rule.calendar_source
        CalendarHub::Sync::FilterSyncService.new(source: filter_rule.calendar_source).sync_filter_rules
      else
        CalendarSource.active.find_each do |source|
          CalendarHub::Sync::FilterSyncService.new(source: source).sync_filter_rules
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("[SyncFilterRulesJob] Filter rule #{filter_rule_id} not found, skipping sync")
  end
end
