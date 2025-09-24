# frozen_string_literal: true

class CalendarSourcesController < ApplicationController
  before_action :set_calendar_source, only: [:show, :edit, :update, :destroy, :sync, :force_sync, :check_destination, :toggle_active, :purge]

  def index
    @calendar_sources = CalendarSource.includes(:sync_attempts, :calendar_events).order(:name)
    @new_source = CalendarSource.new
  end

  def show; end

  def new
    @calendar_source = CalendarSource.new
  end

  def edit; end

  def create
    @calendar_source = CalendarSource.new(calendar_source_params)
    apply_credentials(@calendar_source)

    if @calendar_source.save
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.prepend(
              "sources-list",
              render_to_string(partial: "calendar_sources/source", locals: { source: @calendar_source }),
            ),
            turbo_stream.append(
              "toast-anchor",
              partial: "shared/toast",
              locals: { message: t("flashes.calendar_sources.created") },
            ),
            turbo_stream.replace(
              "new_source_form",
              render_to_string(partial: "calendar_sources/form", locals: { calendar_source: CalendarSource.new }),
            ),
          ])
        end
        format.html { redirect_to(calendar_events_path, notice: t("flashes.calendar_sources.created")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(
            turbo_stream: turbo_stream.replace(
              "new_source_form",
              render_to_string(partial: "calendar_sources/form", locals: { calendar_source: @calendar_source }),
            ),
            status: :unprocessable_entity,
          )
        end
        format.html { render(:new, status: :unprocessable_entity) }
      end
    end
  end

  def update
    apply_credentials(@calendar_source)

    if @calendar_source.update(calendar_source_params)
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.calendar_sources.updated") }),
          ])
        end
        format.html { redirect_to(calendar_events_path(source_id: @calendar_source.id), notice: t("flashes.calendar_sources.updated")) }
      end
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @calendar_source.soft_delete!
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: turbo_stream.append(
          "toast-anchor",
          partial: "shared/toast",
          locals: { message: t("flashes.calendar_sources.archived"), variant: :success },
        ))
      end
      format.html { redirect_to(calendar_events_path, notice: t("flashes.calendar_sources.archived")) }
    end
  end

  def purge
    PurgeCalendarSourceJob.perform_later(@calendar_source.id)
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: turbo_stream.append(
          "toast-anchor",
          partial: "shared/toast",
          locals: { message: t("flashes.calendar_sources.purge_scheduled"), variant: :success },
        ))
      end
      format.html { redirect_to(calendar_events_path, notice: t("flashes.calendar_sources.purge_scheduled")) }
    end
  end

  def sync_all
    queued = CalendarSource.active.to_a.count(&:schedule_sync)
    message = if queued.positive?
      t("flashes.calendar_sources.sync_scheduled", count: queued)
    else
      t("flashes.calendar_sources.sync_skipped")
    end

    redirect_back(fallback_location: calendar_events_path, notice: message)
  end

  def sync
    attempt = @calendar_source.schedule_sync
    respond_to do |format|
      if attempt
        format.turbo_stream do
          render(turbo_stream: turbo_stream.replace(
            "sync_status_source_#{@calendar_source.id}",
            partial: "calendar_sources/sync_status",
            locals: { attempt: attempt },
          ))
        end
        format.html { redirect_back(fallback_location: calendar_events_path(source_id: @calendar_source.id), notice: t("flashes.calendar_sources.sync_scheduled", count: 1)) }
      else
        format.turbo_stream { head(:unprocessable_entity) }
        format.html { redirect_back(fallback_location: calendar_events_path(source_id: @calendar_source.id), alert: t("flashes.calendar_sources.sync_inactive")) }
      end
    end
  end

  def force_sync
    attempt = @calendar_source.schedule_sync(force: true)
    respond_to do |format|
      if attempt
        format.turbo_stream do
          render(turbo_stream: turbo_stream.replace(
            "sync_status_source_#{@calendar_source.id}",
            partial: "calendar_sources/sync_status",
            locals: { attempt: attempt },
          ))
        end
        format.html { redirect_back(fallback_location: calendar_events_path(source_id: @calendar_source.id), notice: t("flashes.calendar_sources.sync_scheduled", count: 1)) }
      else
        format.turbo_stream { head(:unprocessable_entity) }
        format.html { redirect_back(fallback_location: calendar_events_path(source_id: @calendar_source.id), alert: t("flashes.calendar_sources.sync_inactive")) }
      end
    end
  end

  def check_destination
    client = AppleCalendar::Client.new
    url = client.send(:discover_calendar_url, @calendar_source.calendar_identifier)
    notice = "Apple Calendar reachable. Destination found: #{URI.parse(url).request_uri}"
    redirect_back(fallback_location: calendar_sources_path, notice: notice)
  rescue => e
    alert = "Apple Calendar problem: #{e.message}"
    redirect_back(fallback_location: calendar_sources_path, alert: alert)
  end

  def toggle_active
    @calendar_source.update!(active: !@calendar_source.active?)
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.replace(
            view_context.dom_id(@calendar_source, :card),
            partial: "calendar_sources/source",
            locals: { source: @calendar_source },
          ),
          turbo_stream.append(
            "toast-anchor",
            partial: "shared/toast",
            locals: { message: @calendar_source.active? ? "Source resumed" : "Source paused" },
          ),
        ])
      end
      format.html { redirect_back(fallback_location: calendar_events_path, notice: t("flashes.calendar_sources.status_updated")) }
    end
  end

  private

  def set_calendar_source
    scope = action_name == "purge" ? CalendarSource.unscoped : CalendarSource
    @calendar_source = scope.find(params[:id])
  end

  def calendar_source_params
    params.expect(calendar_source: [
      :name,
      :ingestion_url,
      :calendar_identifier,
      :time_zone,
      :active,
      :sync_window_start_hour,
      :sync_window_end_hour,
    ])
  end

  def apply_credentials(source)
    return if params[:calendar_source].blank?

    raw_credentials = params[:calendar_source].fetch(:credentials, ActionController::Parameters.new)
    sanitized = raw_credentials.permit(:http_basic_username, :http_basic_password).to_h
    sanitized.transform_values! { |v| v.is_a?(String) ? v.strip.presence : v }
    sanitized.compact!

    if sanitized[:http_basic_password].blank? && source.persisted?
      sanitized[:http_basic_password] = source.credentials&.dig("http_basic_password")
    end

    return if sanitized.blank?

    existing = source.credentials || {}
    source.credentials = existing.merge(sanitized)
  end
end
