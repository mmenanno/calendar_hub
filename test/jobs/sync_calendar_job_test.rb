# frozen_string_literal: true

require "test_helper"

class SyncCalendarJobTest < ActiveJob::TestCase
  test "invokes sync service" do
    source = calendar_sources(:jane_app)
    CalendarHub::SyncService.expects(:new).with(source: source, observer: kind_of(SyncAttempt)).returns(mock(call: true))

    SyncCalendarJob.perform_now(source.id)
  end
end
