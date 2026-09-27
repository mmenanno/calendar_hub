# frozen_string_literal: true

require "test_helper"

class CalendarSourceLatestSyncAttemptTest < ActiveSupport::TestCase
  setup do
    @provider = calendar_sources(:provider)
    @ics_feed = calendar_sources(:ics_feed)
    SyncAttempt.where(calendar_source: [@provider, @ics_feed]).delete_all
  end

  test "preload_latest_sync_attempts assigns the newest attempt per source" do
    SyncAttempt.create!(calendar_source: @provider, status: :failed, created_at: 2.days.ago)
    newest = SyncAttempt.create!(calendar_source: @provider, status: :success, created_at: 1.hour.ago)
    SyncAttempt.create!(calendar_source: @provider, status: :success, created_at: 3.days.ago)
    feed_attempt = SyncAttempt.create!(calendar_source: @ics_feed, status: :failed, created_at: 5.minutes.ago)

    sources = CalendarSource.preload_latest_sync_attempts(CalendarSource.where(id: [@provider.id, @ics_feed.id]))
    by_id = sources.index_by(&:id)

    assert_no_queries do
      assert_equal(newest, by_id[@provider.id].latest_sync_attempt)
      assert_equal(feed_attempt, by_id[@ics_feed.id].latest_sync_attempt)
    end
  end

  test "preload_latest_sync_attempts matches the association when created_at ties" do
    at = 1.hour.ago
    SyncAttempt.create!(calendar_source: @provider, status: :failed, created_at: at)
    second = SyncAttempt.create!(calendar_source: @provider, status: :success, created_at: at)

    source = CalendarSource.preload_latest_sync_attempts([CalendarSource.find(@provider.id)]).first

    assert_equal(second, source.latest_sync_attempt)
    assert_equal(second, CalendarSource.find(@provider.id).latest_sync_attempt)
  end

  test "preload_latest_sync_attempts marks sources without attempts as loaded nil" do
    source = CalendarSource.preload_latest_sync_attempts(CalendarSource.where(id: @provider.id)).first

    assert_no_queries { assert_nil(source.latest_sync_attempt) }
  end

  test "preload_latest_sync_attempts uses a constant number of queries" do
    5.times { |i| SyncAttempt.create!(calendar_source: @provider, status: :success, created_at: i.hours.ago) }
    SyncAttempt.create!(calendar_source: @ics_feed, status: :success)

    assert_queries_count(3) do
      CalendarSource.preload_latest_sync_attempts(CalendarSource.order(:name))
    end
  end

  test "preload_latest_sync_attempts handles an empty list" do
    assert_empty(CalendarSource.preload_latest_sync_attempts(CalendarSource.none))
  end
end
