# frozen_string_literal: true

class CalendarEventsController < ApplicationController
  def index
    @calendar_sources = CalendarSource.order(:name)
    @selected_source = CalendarSource.find_by(id: params[:source_id]) if params[:source_id].present?

    scope = CalendarEvent.upcoming
    scope = scope.where(calendar_source_id: @selected_source.id) if @selected_source
    if params[:q].present?
      q = "%#{params[:q].strip}%"
      scope = scope.where("title LIKE ? OR location LIKE ?", q, q)
    end
    @events = scope.includes(:calendar_source).limit(200)
  end

  def show
    @event = CalendarEvent.find(params[:id])
  end

  def toggle_sync
    @event = CalendarEvent.find(params[:id])
    @event.update!(sync_exempt: !@event.sync_exempt?)
    respond_to do |format|
      msg = @event.sync_exempt? ? t("flashes.events.excluded") : t("flashes.events.included")
      format.turbo_stream do
        streams = []
        # Index cards: replace the card frame if present
        streams << turbo_stream.replace(@event, partial: "calendar_events/calendar_event", locals: { calendar_event: @event })
        # Show page: replace the dedicated show frame if present
        streams << turbo_stream.replace(view_context.dom_id(@event, :show), partial: "calendar_events/show_frame", locals: { event: @event })
        # Show page header badge
        streams << turbo_stream.replace(view_context.dom_id(@event, :badge), partial: "calendar_events/badge", locals: { event: @event })
        # Toast notification
        streams << turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: msg })
        render(turbo_stream: streams)
      end
      format.html { redirect_to(calendar_event_path(@event), notice: msg) }
    end
  end
end
