# frozen_string_literal: true

require "test_helper"

class SyncFailureAlertsTest < ActionDispatch::IntegrationTest
  test "layout shows the latest attempt's message and first failures for each failing source" do
    source = calendar_sources(:provider)
    source.update!(consecutive_sync_failures: 2)
    SyncAttempt.where(calendar_source: source).delete_all
    SyncAttempt.create!(calendar_source: source, status: :failed, message: "old failure", created_at: 1.day.ago)
    latest = SyncAttempt.create!(calendar_source: source, status: :failed, message: "feed returned 500", errors_count: 5)
    5.times do |i|
      latest.sync_event_results.create!(external_id: "uid-#{i}", action: "upsert", success: false, error_message: "error #{i}", occurred_at: Time.current)
    end

    get calendar_sources_path

    assert_response(:success)
    assert_select("#sync_failure_alert_#{source.id}") do
      assert_select("p", text: /uid-0: error 0/)
      assert_select("p", text: /uid-2: error 2/)
      assert_select("p", text: /uid-3/, count: 0)
      assert_select("p", text: /and 2 more/)
    end
  end

  test "layout ignores older attempts of a failing source" do
    source = calendar_sources(:provider)
    source.update!(consecutive_sync_failures: 1)
    SyncAttempt.create!(calendar_source: source, status: :failed, message: "old failure", created_at: 1.day.ago)
    SyncAttempt.create!(calendar_source: source, status: :failed, message: "new failure")

    get calendar_sources_path

    assert_select("#sync_failure_alert_#{source.id} p", text: "new failure")
    refute_match("old failure", response.body)
  end

  test "layout renders no alerts when no source is failing" do
    CalendarSource.failing.find_each { |source| source.update!(consecutive_sync_failures: 0) }

    get calendar_sources_path

    assert_response(:success)
    assert_select("#sync-failure-alerts", count: 0)
  end
end
