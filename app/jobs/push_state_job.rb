# frozen_string_literal: true

class PushStateJob < ApplicationJob
  include SyncAttemptManageable

  queue_as :sync

  def perform(calendar_source_id, **options)
    source = CalendarSource.find(calendar_source_id)
    attempt = find_or_create_sync_attempt(source, options[:attempt_id])
    return if attempt.nil? # another job owns the source's active attempt

    with_error_tracking(context: "push_state calendar_source_id=#{calendar_source_id}") do
      service = CalendarHub::Sync::PushStateService.new(source: source, observer: attempt)
      service.call
      attempt.finish(status: :success)
    end
  rescue StandardError => exception
    attempt&.finish(status: :failed, message: exception.message) unless attempt&.finished_at
    raise
  end
end
