# frozen_string_literal: true

require "test_helper"

class SyncMetricTest < ActiveSupport::TestCase
  def setup
    @source = calendar_sources(:provider)
    SyncMetric.destroy_all
  end

  test "validates presence of occurred_at" do
    metric = SyncMetric.new(calendar_source: @source)

    refute_predicate(metric, :valid?)
    assert_includes(metric.errors[:occurred_at], "can't be blank")
  end

  test "belongs to calendar_source" do
    metric = SyncMetric.create!(
      calendar_source: @source,
      occurred_at: Time.current,
      upserts_count: 5,
      deletes_count: 1,
      errors_count: 0,
      duration_ms: 1200,
    )

    assert_equal(@source, metric.calendar_source)
  end

  test "for_source scope filters by source id" do
    other_source = calendar_sources(:ics_feed)

    SyncMetric.create!(calendar_source: @source, occurred_at: Time.current, upserts_count: 1)
    SyncMetric.create!(calendar_source: other_source, occurred_at: Time.current, upserts_count: 2)

    results = SyncMetric.for_source(@source.id)

    assert_equal(1, results.count)
    assert_equal(1, results.first.upserts_count)
  end

  test "last_7_days scope filters by date" do
    SyncMetric.create!(calendar_source: @source, occurred_at: 3.days.ago, upserts_count: 1)
    SyncMetric.create!(calendar_source: @source, occurred_at: 10.days.ago, upserts_count: 2)

    results = SyncMetric.last_7_days

    assert_equal(1, results.count)
  end

  test "daily_trend returns aggregated data for last N days" do
    SyncMetric.create!(calendar_source: @source, occurred_at: Date.current.beginning_of_day + 10.hours, upserts_count: 5, deletes_count: 1, errors_count: 0, duration_ms: 1000)
    SyncMetric.create!(calendar_source: @source, occurred_at: Date.current.beginning_of_day + 14.hours, upserts_count: 3, deletes_count: 2, errors_count: 1, duration_ms: 2000)

    trend = SyncMetric.daily_trend(@source.id, days: 7)

    assert_equal(8, trend.length) # 7 days + today

    today_data = trend.find { |d| d[:date] == Date.current.to_s }

    assert_equal(2, today_data[:syncs])
    assert_equal(8, today_data[:upserts])
    assert_equal(3, today_data[:deletes])
    assert_equal(1, today_data[:errors])
  end

  test "daily_trend fills in missing days with zeros" do
    SyncMetric.create!(calendar_source: @source, occurred_at: Date.current.beginning_of_day + 10.hours, upserts_count: 1)

    trend = SyncMetric.daily_trend(@source.id, days: 7)

    zero_days = trend.select { |d| d[:syncs] == 0 }

    assert_equal(7, zero_days.length) # all days except today
  end

  test "daily_trend returns empty results when no metrics" do
    trend = SyncMetric.daily_trend(@source.id, days: 7)

    assert_equal(8, trend.length)
    trend.each { |d| assert_equal(0, d[:syncs]) }
  end
end
