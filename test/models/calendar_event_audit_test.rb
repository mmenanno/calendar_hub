# frozen_string_literal: true

require "test_helper"

class CalendarEventAuditTest < ActiveSupport::TestCase
  def setup
    @calendar_event = calendar_events(:provider_consult)
  end

  test "belongs to calendar_event" do
    audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :created,
      occurred_at: Time.current,
    )

    assert_equal(@calendar_event, audit.calendar_event)
  end

  test "requires calendar_event" do
    audit = CalendarEventAudit.new(action: :created)

    refute_predicate(audit, :valid?)
    assert_includes(audit.errors[:calendar_event], "must exist")
  end

  test "has created action enum" do
    audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :created,
      occurred_at: Time.current,
    )

    assert_predicate(audit, :created?)
    assert_equal("created", audit.action)
  end

  test "has updated action enum" do
    audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :updated,
      occurred_at: Time.current,
    )

    assert_predicate(audit, :updated?)
    assert_equal("updated", audit.action)
  end

  test "has deleted action enum" do
    audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :deleted,
      occurred_at: Time.current,
    )

    assert_predicate(audit, :deleted?)
    assert_equal("deleted", audit.action)
  end

  test "action enum accepts string values" do
    audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: "created",
      occurred_at: Time.current,
    )

    assert_predicate(audit, :created?)
    assert_equal("created", audit.action)
  end

  test "inherits from ApplicationRecord" do
    assert_operator(CalendarEventAudit, :<, ApplicationRecord)
  end

  test "can create multiple audits for same event" do
    audit1 = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :created,
      occurred_at: Time.current,
    )

    audit2 = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :updated,
      occurred_at: Time.current,
    )

    assert_predicate(audit1, :valid?)
    assert_predicate(audit2, :valid?)
    assert_equal(@calendar_event, audit1.calendar_event)
    assert_equal(@calendar_event, audit2.calendar_event)
  end

  test "enum provides scope methods" do
    created_audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :created,
      occurred_at: Time.current,
    )

    updated_audit = CalendarEventAudit.create!(
      calendar_event: @calendar_event,
      action: :updated,
      occurred_at: Time.current,
    )

    created_audits = CalendarEventAudit.created
    updated_audits = CalendarEventAudit.updated

    assert_includes(created_audits, created_audit)
    refute_includes(created_audits, updated_audit)

    assert_includes(updated_audits, updated_audit)
    refute_includes(updated_audits, created_audit)
  end
end
