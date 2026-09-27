# frozen_string_literal: true

require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  test "inherits from ActiveJob::Base" do
    assert_operator(ApplicationJob, :<, ActiveJob::Base)
  end

  class DeadlockingJob < ApplicationJob
    def perform
      raise ActiveRecord::Deadlocked, "deadlock"
    end
  end

  test "retries deadlocks by re-enqueuing the job" do
    assert_enqueued_with(job: DeadlockingJob) do
      DeadlockingJob.perform_now
    end
  end

  class RecordJob < ApplicationJob
    def perform(record)
      record
    end
  end

  test "discards jobs whose record argument no longer exists" do
    job_data = RecordJob.new(calendar_sources(:provider)).serialize
    job_data["arguments"] = [{ "_aj_globalid" => "gid://#{GlobalID.app}/CalendarSource/0" }]

    assert_no_enqueued_jobs do
      assert_nothing_raised { ActiveJob::Base.execute(job_data) }
    end
  end

  class TestJob < ApplicationJob
    def perform(message)
      message.upcase
    end
  end

  test "concrete job can inherit from ApplicationJob" do
    assert_operator(TestJob, :<, ApplicationJob)

    job = TestJob.new("hello")

    assert_equal("HELLO", job.perform("hello"))
  end

  test "can enqueue job that inherits from ApplicationJob" do
    assert_enqueued_jobs(1) do
      TestJob.perform_later("test")
    end
  end
end
