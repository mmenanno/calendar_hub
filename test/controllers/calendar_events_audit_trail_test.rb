# frozen_string_literal: true

require "test_helper"

class CalendarEventsAuditTrailTest < ActionDispatch::IntegrationTest
  setup do
    @event = calendar_events(:provider_consult)
    CalendarEventAudit.where(calendar_event: @event).delete_all
  end

  test "show lists every audit when under the limit" do
    create_audits(2)

    get calendar_event_path(@event)

    assert_response(:success)
    assert_select("span.capitalize", text: "updated", count: 2)
    refute_match("Showing the latest", response.body)
  end

  test "show limits the audit trail to the latest entries and says so" do
    limit = CalendarEventsController::AUDIT_TRAIL_LIMIT
    create_audits(limit + 5)

    get calendar_event_path(@event)

    assert_response(:success)
    assert_select("span.capitalize", text: "updated", count: limit)
    assert_match("Showing the latest #{limit} of #{limit + 5} changes.", response.body)
  end

  private

  def create_audits(count)
    count.times do |i|
      CalendarEventAudit.create!(calendar_event: @event, action: :updated, occurred_at: (count - i).hours.ago)
    end
  end
end
