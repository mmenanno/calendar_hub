# frozen_string_literal: true

require "test_helper"

class CalendarEventPresenterAllDayTest < ActiveSupport::TestCase
  setup do
    @source = calendar_sources(:ics_feed)
    @view_context = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
  end

  test "displays single-day all-day event correctly" do
    event = CalendarEvent.create!(
      calendar_source: @source,
      external_id: "single-all-day",
      title: "Single All Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 28, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    presenter = CalendarEventPresenter.new(event, @view_context)

    assert_equal("All day", presenter.time_display)
    assert_equal("All day", presenter.duration_precise)
  end

  test "displays multi-day all-day event correctly" do
    event = CalendarEvent.create!(
      calendar_source: @source,
      external_id: "multi-all-day",
      title: "Multi Day Event",
      starts_at: Time.utc(2025, 9, 27, 0, 0, 0),
      ends_at: Time.utc(2025, 9, 30, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    presenter = CalendarEventPresenter.new(event, @view_context)

    assert_match(/September 27, 2025.*September 30, 2025/, presenter.time_display)
    assert_equal("3 days", presenter.duration_precise)
  end

  test "displays timed event correctly" do
    event = CalendarEvent.create!(
      calendar_source: @source,
      external_id: "timed-event",
      title: "Timed Event",
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 15, 30, 0),
      time_zone: "UTC",
      all_day: false,
    )

    presenter = CalendarEventPresenter.new(event, @view_context)

    assert_match(/September 27, 2025.*14:00/, presenter.time_display)
    assert_equal("1 hour 30 minutes", presenter.duration_precise)
  end

  test "formats all-day event dates without times" do
    event = CalendarEvent.create!(
      calendar_source: @source,
      external_id: "format-test",
      title: "Format Test",
      starts_at: Time.utc(2025, 12, 25, 0, 0, 0),
      ends_at: Time.utc(2025, 12, 26, 0, 0, 0),
      time_zone: "UTC",
      all_day: true,
    )

    presenter = CalendarEventPresenter.new(event, @view_context)

    # Should not include time components for all-day events
    starts_display = presenter.starts_at_long
    ends_display = presenter.ends_at_long

    refute_match(/\d{1,2}:\d{2}/, starts_display, "All-day start should not include time")
    refute_match(/\d{1,2}:\d{2}/, ends_display, "All-day end should not include time")
    assert_match(/December 25, 2025/, starts_display)
    assert_match(/December 26, 2025/, ends_display)
  end
end
