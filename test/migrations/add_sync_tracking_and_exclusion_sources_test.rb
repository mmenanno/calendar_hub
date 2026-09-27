# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260927010000_add_sync_tracking_and_exclusion_sources_to_calendar_events")

class AddSyncTrackingAndExclusionSourcesTest < ActiveSupport::TestCase
  test "backfill splits sync_exempt into rule exclusion and manual overrides" do
    source = calendar_sources(:provider)
    FilterRule.create!(calendar_source: source, pattern: "Secret", field_name: "title", match_type: "contains", active: true)
    ruled = CalendarEvent.create!(calendar_source: source, external_id: "ruled", title: "Secret meeting", starts_at: Time.current, ends_at: 1.hour.from_now)
    manual = CalendarEvent.create!(calendar_source: source, external_id: "manual", title: "Lunch", starts_at: Time.current, ends_at: 1.hour.from_now)
    included = CalendarEvent.create!(calendar_source: source, external_id: "included", title: "Secret but wanted", starts_at: Time.current, ends_at: 1.hour.from_now)
    CalendarEvent.where(id: [ruled.id, manual.id]).update_all(sync_exempt: true, excluded_by_rule: false, manual_sync_override: nil)
    CalendarEvent.where(id: included.id).update_all(sync_exempt: false, excluded_by_rule: false, manual_sync_override: nil)

    AddSyncTrackingAndExclusionSourcesToCalendarEvents.new.send(:backfill_exclusion_sources)

    assert_equal([true, nil], ruled.reload.values_at(:excluded_by_rule, :manual_sync_override))
    assert_equal([false, "exclude"], manual.reload.values_at(:excluded_by_rule, :manual_sync_override))
    assert_equal([true, "include"], included.reload.values_at(:excluded_by_rule, :manual_sync_override))
  end
end
