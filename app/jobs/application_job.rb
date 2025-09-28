# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include ErrorTrackable

  # Common retry configuration for transient errors
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3
  retry_on ActiveRecord::ConnectionTimeoutError, wait: :exponentially_longer, attempts: 3

  # Discard jobs for deleted records or serialization issues
  discard_on ActiveJob::DeserializationError
  # NOTE: RecordNotFound should bubble up for proper error handling in tests
  # discard_on ActiveRecord::RecordNotFound

  # Default queue for all jobs
  queue_as :default
end
