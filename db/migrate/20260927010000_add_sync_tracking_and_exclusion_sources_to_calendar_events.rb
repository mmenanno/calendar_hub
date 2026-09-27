# frozen_string_literal: true

# - synced_fingerprint: digest of the payload last pushed to Apple Calendar,
#   so unchanged events are not re-PUT on every sync.
# - excluded_by_rule / manual_sync_override: split the single sync_exempt flag
#   into rule-driven exclusion and a manual include/exclude override.
#   sync_exempt stays as the derived, effective value.
class AddSyncTrackingAndExclusionSourcesToCalendarEvents < ActiveRecord::Migration[8.1]
  class MigrationFilterRule < ActiveRecord::Base
    self.table_name = "filter_rules"
  end

  class MigrationCalendarEvent < ActiveRecord::Base
    self.table_name = "calendar_events"
  end

  def up
    add_column(:calendar_events, :synced_fingerprint, :string)
    add_column(:calendar_events, :excluded_by_rule, :boolean, default: false, null: false)
    add_column(:calendar_events, :manual_sync_override, :string)

    backfill_exclusion_sources
  end

  def down
    remove_column(:calendar_events, :manual_sync_override)
    remove_column(:calendar_events, :excluded_by_rule)
    remove_column(:calendar_events, :synced_fingerprint)
  end

  private

  # Previously sync_exempt mixed rule and manual decisions. Re-evaluate the
  # active rules: exempt events no rule matches were excluded manually; non
  # exempt events a rule matches were included manually.
  def backfill_exclusion_sources
    rules = MigrationFilterRule.where(active: true).to_a
    MigrationCalendarEvent.reset_column_information

    MigrationCalendarEvent.find_each do |event|
      matched = rules.any? { |rule| rule_applies?(rule, event) && rule_matches?(rule, event) }
      override = if event.sync_exempt && !matched
        "exclude"
      elsif !event.sync_exempt && matched
        "include"
      end
      next if !matched && override.nil?

      event.update_columns(excluded_by_rule: matched, manual_sync_override: override)
    end
  end

  def rule_applies?(rule, event)
    rule.calendar_source_id.nil? || rule.calendar_source_id == event.calendar_source_id
  end

  def rule_matches?(rule, event)
    value = event.public_send(rule.field_name).to_s if ["title", "description", "location"].include?(rule.field_name)
    return false if value.blank?

    pattern = rule.pattern.to_s
    case rule.match_type
    when "equals"
      rule.case_sensitive ? value == pattern : value.casecmp?(pattern)
    when "contains"
      rule.case_sensitive ? value.include?(pattern) : value.downcase.include?(pattern.downcase)
    when "regex"
      Regexp.new(pattern, rule.case_sensitive ? nil : Regexp::IGNORECASE, timeout: 1.0).match?(value)
    else
      false
    end
  rescue RegexpError # includes Regexp::TimeoutError
    false
  end
end
