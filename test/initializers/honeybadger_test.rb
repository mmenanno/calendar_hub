# frozen_string_literal: true

require "test_helper"

class HoneybadgerInitializerTest < ActiveSupport::TestCase
  def notice_for(error, **context)
    Honeybadger::Notice.new(Honeybadger.config, exception: error, context: context)
  end

  def run_hooks(notice)
    Honeybadger.config.before_notify_hooks.each { |hook| hook.call(notice) }
    notice
  end

  def connection_error
    CalendarHub::Ingestion::FeedConnectionError.new("HTTP connection failed: execution expired")
  end

  test "drops feed connection errors from sync attempts that will be retried" do
    notice = run_hooks(notice_for(connection_error, job_class: "SyncCalendarJob", executions: 1))

    assert_predicate(notice, :halted?)
  end

  test "reports feed connection errors once sync retries are exhausted" do
    notice = run_hooks(notice_for(connection_error, job_class: "SyncCalendarJob", executions: SyncCalendarJob::MAX_ATTEMPTS))

    refute_predicate(notice, :halted?)
  end

  test "reports other errors from early sync attempts" do
    notice = run_hooks(notice_for(RuntimeError.new("boom"), job_class: "SyncCalendarJob", executions: 1))

    refute_predicate(notice, :halted?)
  end
end
