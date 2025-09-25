# frozen_string_literal: true

module Admin
  class JobsController < ApplicationController
    def index
      @queued = SolidQueue::Job.where(finished_at: nil).count
      @running = SolidQueue::Process.count
      @failed  = SolidQueue::FailedExecution.count
      @recent_attempts = SyncAttempt.order(created_at: :desc).limit(20)
      @recent_metrics = Rails.cache.read("calendar_hub:last_sync_metrics") || []
      ids = @recent_metrics.pluck(:source_id).uniq
      @source_names = CalendarSource.unscoped.where(id: ids).pluck(:id, :name).to_h
    end

    def clear_metrics
      Rails.cache.delete("calendar_hub:last_sync_metrics")
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.admin.metrics_cleared") }))
        end
        format.html { redirect_to(admin_jobs_path, notice: t("flashes.admin.metrics_cleared")) }
      end
    end
  end
end
