# frozen_string_literal: true

class CalendarEventsController < ApplicationController
  def index
    @calendar_sources = CalendarSource.order(:name)
    @selected_source = CalendarSource.find_by(id: params[:source_id]) if params[:source_id].present?

    scope = CalendarEvent.upcoming
    scope = scope.where(calendar_source_id: @selected_source.id) if @selected_source

    # Hide excluded events by default unless explicitly shown
    show_excluded = params[:show_excluded] == "true"
    scope = scope.where(sync_exempt: false) unless show_excluded

    @events = scope.includes(:calendar_source).limit(200)

    if params[:q].present?
      @events = filter_events_by_search(@events, params[:q].strip)
    end
    @show_excluded = show_excluded

    if turbo_frame_request_id == "events-list"
      render(partial: "events_list", locals: { events: @events, selected_source: @selected_source })
    end
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

  private

  def filter_events_by_search(events, search_term)
    return events if search_term.blank?

    search_term = search_term.downcase

    events.select do |event|
      search_data = event_search_data(event)

      search_data[:original_title].include?(search_term) ||
        search_data[:mapped_title].include?(search_term) ||
        search_data[:location].include?(search_term)
    end
  end

  def event_search_data(event)
    cache_key = "event_search_data/#{event.id}/#{event.updated_at.to_i}"
    Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
      {
        original_title: event.title.to_s.downcase,
        mapped_title: CalendarHub::NameMapper.apply(event.title, source: event.calendar_source).to_s.downcase,
        location: event.location.to_s.downcase,
      }
    end
  end
end
