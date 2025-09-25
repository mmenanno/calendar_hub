# frozen_string_literal: true

module Admin
  class JobsController < ApplicationController
    def index
      # Job Queue Stats
      @queued = SolidQueue::Job.where(finished_at: nil).count
      @completed = SolidQueue::Job.where.not(finished_at: nil).where("finished_at > ?", 24.hours.ago).count
      @failed = SolidQueue::FailedExecution.count
      @processes = SolidQueue::Process.count

      # Auto-sync specific stats
      @auto_sync_scheduler_jobs = SolidQueue::Job.where(class_name: "AutoSyncSchedulerJob").where("created_at > ?", 24.hours.ago).count
      @sync_calendar_jobs = SolidQueue::Job.where(class_name: "SyncCalendarJob").where("created_at > ?", 24.hours.ago).count

      # Sync Attempt Analysis
      @recent_attempts = SyncAttempt.includes(:calendar_source).order(created_at: :desc).limit(20)

      # Auto-sync vs Manual sync breakdown (last 24 hours)
      recent_attempts_24h = SyncAttempt.includes(:calendar_source).where("sync_attempts.created_at > ?", 24.hours.ago)
      @auto_sync_attempts = recent_attempts_24h.joins(:calendar_source).where(calendar_sources: { auto_sync_enabled: true }).count
      @manual_sync_attempts = recent_attempts_24h.count - @auto_sync_attempts

      # Auto-sync sources stats
      @auto_sync_sources_total = CalendarSource.where(auto_sync_enabled: true).count
      @auto_sync_sources_active = CalendarSource.where(auto_sync_enabled: true, active: true).count
      @auto_sync_sources_due = CalendarSource.active.auto_sync_enabled.count(&:sync_due?)

      # Existing metrics
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
