# frozen_string_literal: true

class CalendarEventsController < ApplicationController
  AUDIT_TRAIL_LIMIT = 50
  EVENTS_PER_PAGE = 50
  SEARCH_QUERY_MAX_LENGTH = 200

  helper_method :events_filter_params

  def index
    @calendar_sources = CalendarSource.preload_latest_sync_attempts(CalendarSource.order(:name))
    @selected_source = params[:source_id].present? ? @calendar_sources.find { |s| s.id == params[:source_id].to_i } : nil
    @show_past = params[:show_past] == "true"
    # Hide excluded events by default unless explicitly shown
    @show_excluded = params[:show_excluded] == "true"
    @query = params[:q].to_s.strip.first(SEARCH_QUERY_MAX_LENGTH)
    @page = [params[:page].to_i, 1].max

    # Fetch one extra row to know whether there is a next page.
    events = events_scope.offset((@page - 1) * EVENTS_PER_PAGE).limit(EVENTS_PER_PAGE + 1).to_a
    @next_page = @page + 1 if events.size > EVENTS_PER_PAGE
    @prev_page = @page - 1 if @page > 1
    @events = events.first(EVENTS_PER_PAGE)

    return unless turbo_frame_request_id == "events-list"

    render(
      partial: "events_list",
      locals: {
        events: @events,
        selected_source: @selected_source,
        show_past: @show_past,
        show_excluded: @show_excluded,
        page: @page,
        prev_page: @prev_page,
        next_page: @next_page,
      },
    )
  end

  def show
    @event = CalendarEvent.find(params.expect(:id))
    audits = CalendarEventAudit.where(calendar_event_id: @event.id)
    # Latest AUDIT_TRAIL_LIMIT entries, displayed oldest first.
    @audits = audits.order(occurred_at: :desc, id: :desc).limit(AUDIT_TRAIL_LIMIT).to_a.reverse
    @audits_total = @audits.size < AUDIT_TRAIL_LIMIT ? @audits.size : audits.count
  end

  def toggle_sync
    @event = CalendarEvent.find(params.expect(:id))
    # Stored as a manual override so filter-rule re-evaluation cannot undo it.
    @event.toggle_sync_exempt!
    SyncEventToAppleJob.perform_later(@event.id)
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

  # The current list filters as URL params (page excluded), so links can
  # change one of them and keep the rest.
  def events_filter_params
    {
      source_id: @selected_source&.id,
      q: @query.presence,
      show_excluded: (true if @show_excluded),
      show_past: (true if @show_past),
    }.compact
  end

  def events_scope
    scope = if @show_past
      CalendarEvent.where(starts_at: ...Time.current.beginning_of_day).order(starts_at: :desc, id: :desc)
    else
      # id breaks starts_at ties so pages don't overlap or skip events
      CalendarEvent.upcoming.order(:id)
    end
    scope = scope.where(calendar_source_id: @selected_source.id) if @selected_source
    scope = scope.where(sync_exempt: false) unless @show_excluded
    scope = scope.where(search_condition(@query)) if @query.present?
    scope.includes(:calendar_source)
  end

  # Case-insensitive substring match (ASCII only, like SQLite's LIKE) on
  # title, location and description, plus the title shown after mappings.
  def search_condition(query)
    table = CalendarEvent.arel_table
    pattern = "%#{CalendarEvent.sanitize_sql_like(query)}%"
    conditions = [:title, :location, :description].map { |column| table[column].matches(pattern, "\\") }
    conditions.concat(mapped_title_conditions(query))
    conditions.reduce { |memo, condition| memo.or(condition) }
  end

  # Events are displayed with CalendarHub::NameMapper applied, so a search for
  # "Standup" should find events a mapping renames to "Standup". For each
  # active mapping whose replacement contains the query, match the events the
  # mapping applies to. Regex mappings are skipped (SQLite has no REGEXP, and
  # the replacement can depend on the original title). An event that an
  # earlier mapping renames to something else is a rare false positive.
  def mapped_title_conditions(query)
    mappings = EventMapping.active.where.not(match_type: "regex").where.not(replacement: [nil, ""])
    mappings = mappings.where(calendar_source_id: [nil, @selected_source.id]) if @selected_source
    needle = query.downcase
    source_column = CalendarEvent.arel_table[:calendar_source_id]

    mappings.select { |mapping| mapping.replacement.downcase.include?(needle) }.map do |mapping|
      condition = mapping_title_condition(mapping)
      mapping.calendar_source_id ? condition.and(source_column.eq(mapping.calendar_source_id)) : condition
    end
  end

  # Mirrors CalendarHub::NameMapper's "equals" and "contains" matching.
  def mapping_title_condition(mapping)
    title = CalendarEvent.arel_table[:title]
    escaped = CalendarEvent.sanitize_sql_like(mapping.pattern)

    if mapping.equals?
      mapping.case_sensitive ? title.eq(mapping.pattern) : title.matches(escaped, "\\")
    elsif mapping.case_sensitive
      Arel::Nodes::NamedFunction.new("instr", [title, Arel::Nodes.build_quoted(mapping.pattern)]).gt(0)
    else
      title.matches("%#{escaped}%", "\\")
    end
  end
end
