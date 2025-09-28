# frozen_string_literal: true

require "test_helper"

class CalendarSourcePresenterTest < ActiveSupport::TestCase
  class FakeView
    def initialize(l_value: "formatted", time_ago_value: "moments", distance_value: "distance")
      @l_value = l_value
      @time_ago_value = time_ago_value
      @distance_value = distance_value
    end

    def l(*_args, **_options)
      @l_value
    end

    def time_ago_in_words(*_args)
      @time_ago_value
    end

    def distance_of_time_in_words(*_args)
      @distance_value
    end

    def status_badge_class(status)
      ApplicationController.helpers.status_badge_class(status)
    end
  end

  def build_source(**attrs)
    CalendarSource.unscoped.create!(
      {
        name: "Presenter Source",
        calendar_identifier: "presenter",
        ingestion_url: "https://example.com/feed.ics",
        settings: {},
      }.merge(attrs),
    )
  end

  def presenter_for(source, view: FakeView.new)
    CalendarSourcePresenter.new(source, view)
  end

  test "calendar_identifier falls back to em dash when blank" do
    source = build_source
    source.stubs(:calendar_identifier).returns(nil)

    presenter = presenter_for(source)

    assert_equal("—", presenter.calendar_identifier)
  end

  test "last_synced_text returns translation when timestamp missing" do
    source = build_source(last_synced_at: nil)
    presenter = presenter_for(source)

    assert_equal(I18n.t("common.states.never"), presenter.last_synced_text)
  end

  test "last_synced_text formats relative time when timestamp present" do
    source = build_source(last_synced_at: 2.hours.ago)
    view = FakeView.new(time_ago_value: "2 hours")
    presenter = presenter_for(source, view: view)

    assert_equal("2 hours ago", presenter.last_synced_text)
  end

  test "next_sync_text returns now when within sync window" do
    source = build_source
    source.stubs(:within_sync_window?).returns(true)
    presenter = presenter_for(source)

    assert_equal(I18n.t("ui.sources.now"), presenter.next_sync_text)
  end

  test "next_sync_text formats time and distance when outside window" do
    source = build_source
    next_time = 30.minutes.from_now
    source.stubs(:within_sync_window?).returns(false)
    source.stubs(:next_sync_time).returns(next_time)
    view = FakeView.new(l_value: "Jan 1 12:00", distance_value: "in 30 minutes")
    presenter = presenter_for(source, view: view)

    assert_equal("Jan 1 12:00 (in 30 minutes)", presenter.next_sync_text)
  end

  test "active state helpers reflect active source" do
    presenter = presenter_for(build_source(active: true, deleted_at: nil))

    assert_equal("bg-emerald-500/10 text-emerald-300", presenter.active_badge_class)
    assert_equal(I18n.t("common.states.active"), presenter.active_label)
    assert_equal("bg-emerald-400", presenter.active_dot_class)
  end

  test "active state helpers reflect paused source" do
    presenter = presenter_for(build_source(active: false, deleted_at: nil))

    assert_equal("bg-slate-800 text-slate-400", presenter.active_badge_class)
    assert_equal(I18n.t("common.states.paused"), presenter.active_label)
    assert_equal("bg-slate-600", presenter.active_dot_class)
  end

  test "active state helpers reflect deleted source" do
    presenter = presenter_for(build_source(active: false, deleted_at: Time.current))

    assert_equal("bg-rose-500/10 text-rose-300", presenter.active_badge_class)
    assert_equal(I18n.t("common.states.archived"), presenter.active_label)
    assert_equal("bg-rose-400", presenter.active_dot_class)
  end

  test "auto_sync_status_text handles disabled, due, scheduled, and paused states" do
    disabled_source = build_source(auto_sync_enabled: false)

    due_source = build_source(auto_sync_enabled: true, active: true, last_synced_at: nil)

    scheduled_source = build_source(auto_sync_enabled: true, active: true, last_synced_at: Time.current)
    scheduled_source.update!(sync_frequency_minutes: 120)
    view = FakeView.new(distance_value: "in 2 hours")

    paused_source = build_source(auto_sync_enabled: true, active: false)

    due_presenter = presenter_for(due_source)
    scheduled_presenter = presenter_for(scheduled_source, view: view)
    disabled_presenter = presenter_for(disabled_source)
    paused_presenter = presenter_for(paused_source)

    assert_equal(I18n.t("ui.sources.auto_sync_disabled"), disabled_presenter.auto_sync_status_text)
    assert_equal(I18n.t("ui.sources.auto_sync_due"), due_presenter.auto_sync_status_text)
    expected_scheduled = "#{I18n.t("ui.sources.next_auto_sync")}: in 2 hours"

    assert_equal(expected_scheduled, scheduled_presenter.auto_sync_status_text)
    assert_equal(I18n.t("ui.sources.auto_sync_paused"), paused_presenter.auto_sync_status_text)
  end

  test "auto_sync_badge_class reflects enabled states" do
    disabled_source = build_source(auto_sync_enabled: false)
    due_source = build_source(auto_sync_enabled: true)
    due_source.stubs(:auto_syncable?).returns(true)
    due_source.stubs(:sync_due?).returns(true)

    scheduled_source = build_source(auto_sync_enabled: true)
    scheduled_source.stubs(:auto_syncable?).returns(true)
    scheduled_source.stubs(:sync_due?).returns(false)

    paused_source = build_source(auto_sync_enabled: true)
    paused_source.stubs(:auto_syncable?).returns(false)

    presenter_disabled = presenter_for(disabled_source)
    presenter_due = presenter_for(due_source)
    presenter_scheduled = presenter_for(scheduled_source)
    presenter_paused = presenter_for(paused_source)

    assert_equal("bg-slate-800 text-slate-400", presenter_disabled.auto_sync_badge_class)
    assert_equal("bg-yellow-500/10 text-yellow-300", presenter_due.auto_sync_badge_class)
    assert_equal("bg-indigo-500/10 text-indigo-300", presenter_scheduled.auto_sync_badge_class)
    assert_equal("bg-slate-800 text-slate-400", presenter_paused.auto_sync_badge_class)
  end

  test "auto_sync_dot_class reflects enabled states" do
    disabled_source = build_source(auto_sync_enabled: false)
    due_source = build_source(auto_sync_enabled: true)
    due_source.stubs(:auto_syncable?).returns(true)
    due_source.stubs(:sync_due?).returns(true)

    scheduled_source = build_source(auto_sync_enabled: true)
    scheduled_source.stubs(:auto_syncable?).returns(true)
    scheduled_source.stubs(:sync_due?).returns(false)

    paused_source = build_source(auto_sync_enabled: true)
    paused_source.stubs(:auto_syncable?).returns(false)

    presenter_disabled = presenter_for(disabled_source)
    presenter_due = presenter_for(due_source)
    presenter_scheduled = presenter_for(scheduled_source)
    presenter_paused = presenter_for(paused_source)

    assert_equal("bg-slate-600", presenter_disabled.auto_sync_dot_class)
    assert_equal("bg-yellow-400", presenter_due.auto_sync_dot_class)
    assert_equal("bg-indigo-400", presenter_scheduled.auto_sync_dot_class)
    assert_equal("bg-slate-600", presenter_paused.auto_sync_dot_class)
  end

  test "sync_frequency_text returns em dash when auto sync disabled" do
    source = build_source(auto_sync_enabled: false)
    presenter = presenter_for(source)

    assert_equal("—", presenter.sync_frequency_text)
  end

  test "sync_frequency_text reflects default frequency with suffix for minutes" do
    AppSetting.instance.update!(default_sync_frequency_minutes: 45)
    source = build_source(auto_sync_enabled: true, sync_frequency_minutes: nil)
    presenter = presenter_for(source)

    expected = "#{I18n.t("ui.sources.every_n_minutes", count: 45)} #{I18n.t("ui.sources.default_frequency_suffix")}"

    assert_equal(expected, presenter.sync_frequency_text)
  end

  test "sync_frequency_text formats hours without suffix when custom value provided" do
    source = build_source(auto_sync_enabled: true, sync_frequency_minutes: 180)
    presenter = presenter_for(source)

    assert_equal(I18n.t("ui.sources.every_n_hours", count: 3), presenter.sync_frequency_text)
  end

  test "pending_count delegates to source" do
    source = build_source
    source.stubs(:pending_events_count).returns(7)
    presenter = presenter_for(source)

    assert_equal(7, presenter.pending_count)
  end
end
