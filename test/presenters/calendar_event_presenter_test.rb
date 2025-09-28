# frozen_string_literal: true

require "test_helper"

class CalendarEventPresenterTest < ActiveSupport::TestCase
  include ModelBuilders

  setup do
    @source = calendar_sources(:ics_feed)
    @archived_source = calendar_sources(:archived_source)
    @view_context = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view_context.extend(ApplicationHelper)
  end

  teardown do
    Rails.cache.clear
  end

  def build_presenter_event(**attrs)
    build_event(
      calendar_source: @source,
      title: "Original Title",
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 15, 0, 0),
      **attrs,
    )
  end

  def presenter_for(event)
    CalendarEventPresenter.new(event, @view_context)
  end

  test "starts_at_long formats localized time for timed events" do
    event = build_presenter_event
    presenter = presenter_for(event)

    expected = @view_context.l(event.starts_at.in_time_zone(event.time_zone), format: :long)

    assert_equal(expected, presenter.starts_at_long)
  end

  test "ends_at_long formats localized time for timed events" do
    event = build_presenter_event(ends_at: Time.utc(2025, 9, 27, 16, 0, 0))
    presenter = presenter_for(event)

    expected = @view_context.l(event.ends_at.in_time_zone(event.time_zone), format: :long)

    assert_equal(expected, presenter.ends_at_long)
  end

  test "title caches mapped result" do
    event = build_event(title: "Needs Mapping")
    presenter = presenter_for(event)

    CalendarHub::NameMapper.expects(:apply).once.returns("Mapped Title")

    assert_equal("Mapped Title", presenter.title)
    assert_equal("Mapped Title", presenter.title)
  end

  test "title_mapped? reflects difference between mapped and original" do
    event = build_event(title: "Original Title")
    presenter = presenter_for(event)

    CalendarHub::NameMapper.stubs(:apply).returns("Different Title")

    presenter.title

    assert_predicate(presenter, :title_mapped?)
  end

  test "source_name returns unknown when source missing" do
    event = build_event
    event.stubs(:calendar_source).returns(nil)
    presenter = presenter_for(event)

    assert_equal("Unknown Source", presenter.source_name)
  end

  test "source_name annotates archived sources" do
    event = build_event(calendar_source: @archived_source)
    presenter = presenter_for(event)

    expected = "#{@archived_source.name} (archived)"

    assert_equal(expected, presenter.source_name)
  end

  test "duration_precise returns zero minutes when duration nonpositive" do
    event = build_event(
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 14, 0, 0),
    )
    presenter = presenter_for(event)

    assert_equal("0 minutes", presenter.duration_precise)
  end

  test "duration_precise omits hour component when under an hour" do
    event = build_event(
      starts_at: Time.utc(2025, 9, 27, 14, 0, 0),
      ends_at: Time.utc(2025, 9, 27, 14, 45, 0),
    )
    presenter = presenter_for(event)

    assert_equal("45 minutes", presenter.duration_precise)
  end

  test "last_synced_text falls back to pending when unsynced" do
    event = build_event(synced_at: nil)
    presenter = presenter_for(event)

    assert_equal(I18n.t("common.states.pending"), presenter.last_synced_text)
  end

  test "last_synced_text uses relative time when synced" do
    event = build_event(synced_at: 1.hour.ago)
    presenter = presenter_for(event)

    assert_match(/ago\z/, presenter.last_synced_text)
  end

  test "location returns em dash when blank" do
    event = build_event(location: "")
    presenter = presenter_for(event)

    assert_equal("—", presenter.location)
  end

  test "excluded? reflects sync exemption" do
    event = build_event(sync_exempt: true)
    presenter = presenter_for(event)

    assert_predicate(presenter, :excluded?)
  end

  test "time_display returns formatted start time for timed events" do
    event = build_event
    presenter = presenter_for(event)

    assert_equal(presenter.starts_at_long.to_s, presenter.time_display)
  end
end
