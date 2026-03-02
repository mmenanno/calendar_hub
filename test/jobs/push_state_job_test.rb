# frozen_string_literal: true

require "test_helper"

class PushStateJobTest < ActiveJob::TestCase
  test "invokes push state service with attempt as observer" do
    source = calendar_sources(:provider)
    attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

    service = mock("PushStateService")
    service.expects(:call).returns({ upserts: 1, deletes: 0 })
    CalendarHub::Sync::PushStateService.expects(:new).with(source: source, observer: attempt).returns(service)

    PushStateJob.perform_now(source.id, attempt_id: attempt.id)

    assert_equal "success", attempt.reload.status
  end

  test "marks attempt as failed on error" do
    source = calendar_sources(:provider)
    attempt = SyncAttempt.create!(calendar_source: source, status: :queued)

    service = mock("PushStateService")
    service.expects(:call).raises(StandardError.new("Apple Calendar unavailable"))
    CalendarHub::Sync::PushStateService.expects(:new).with(source: source, observer: attempt).returns(service)

    assert_raises(StandardError) do
      PushStateJob.perform_now(source.id, attempt_id: attempt.id)
    end

    assert_equal "failed", attempt.reload.status
    assert_equal "Apple Calendar unavailable", attempt.message
  end
end
