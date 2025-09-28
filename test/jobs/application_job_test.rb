# frozen_string_literal: true

require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  test "inherits from ActiveJob::Base" do
    assert_operator(ApplicationJob, :<, ActiveJob::Base)
  end

  test "has commented retry_on configuration" do
    file_content = Rails.root.join("app/jobs/application_job.rb").read

    assert_match(/# retry_on ActiveRecord::Deadlocked/, file_content)
  end

  test "has commented discard_on configuration" do
    file_content = Rails.root.join("app/jobs/application_job.rb").read

    assert_match(/# discard_on ActiveJob::DeserializationError/, file_content)
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
