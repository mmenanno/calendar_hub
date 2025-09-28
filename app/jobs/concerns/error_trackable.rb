# frozen_string_literal: true

module ErrorTrackable
  extend ActiveSupport::Concern

  private

  def with_error_tracking(context:)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    Rails.logger.info("[#{self.class.name}] #{context} completed in #{duration_ms}ms")
    result
  rescue ActiveRecord::RecordNotFound
    # Let RecordNotFound bubble up without logging as error
    raise
  rescue => e
    Rails.logger.error("[#{self.class.name}] #{context} failed: #{e.message}")
    raise
  end

  def job_context
    "#{self.class.name}##{begin
      action_name
    rescue
      "perform"
    end}"
  end
end
