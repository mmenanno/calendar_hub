# frozen_string_literal: true

require "test_helper"

class SyncStatusPresenterTest < ActiveSupport::TestCase
  def setup
    @source = calendar_sources(:provider)
  end

  test "badge_class returns emerald for successful attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-emerald-500/10 text-emerald-300", presenter.badge_class)
  end

  test "badge_class returns indigo for running attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :running,
      started_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-indigo-500/10 text-indigo-300", presenter.badge_class)
  end

  test "badge_class returns rose for failed attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :failed,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-rose-500/10 text-rose-300", presenter.badge_class)
  end

  test "badge_class returns slate for queued status" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      started_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-slate-800 text-slate-300", presenter.badge_class)
  end

  test "dot_class returns emerald for successful attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-emerald-400", presenter.dot_class)
  end

  test "dot_class returns indigo for running attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :running,
      started_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-indigo-400", presenter.dot_class)
  end

  test "dot_class returns rose for failed attempts" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :failed,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-rose-400", presenter.dot_class)
  end

  test "dot_class returns slate for queued status" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
      started_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("bg-slate-500", presenter.dot_class)
  end

  test "status_label capitalizes status" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal("Success", presenter.status_label)
  end

  test "status_label handles different statuses" do
    statuses = [:queued, :running, :success, :failed]

    statuses.each do |status|
      attempt = SyncAttempt.create!(
        calendar_source: @source,
        status: status,
        started_at: 1.hour.ago,
        finished_at: (status.in?([:success, :failed]) ? 1.hour.ago : nil),
      )
      presenter = SyncStatusPresenter.new(attempt)

      assert_equal(status.to_s.capitalize, presenter.status_label)
    end
  end

  test "started_ago returns time ago string when started_at is present" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 2.hours.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    result = presenter.started_ago

    assert_match(/about 2 hours ago/, result)
  end

  test "started_ago returns nil when started_at is nil" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :queued,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_nil(presenter.started_ago)
  end

  test "finished_ago returns time ago string when finished_at is present" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 2.hours.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    result = presenter.finished_ago

    assert_match(/about 1 hour ago/, result)
  end

  test "finished_ago returns nil when finished_at is nil" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :running,
      started_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_nil(presenter.finished_ago)
  end

  test "presenter stores attempt reference" do
    attempt = SyncAttempt.create!(
      calendar_source: @source,
      status: :success,
      started_at: 1.hour.ago,
      finished_at: 1.hour.ago,
    )
    presenter = SyncStatusPresenter.new(attempt)

    assert_equal(attempt, presenter.attempt)
  end
end
