# frozen_string_literal: true

require "test_helper"

class CalendarEventsSearchPaginationTest < ActionDispatch::IntegrationTest
  PER_PAGE = CalendarEventsController::EVENTS_PER_PAGE

  setup do
    @source = CalendarSource.create!(name: "Paging Source", calendar_identifier: "paging", ingestion_url: "https://example.com/paging.ics")
  end

  test "search runs in SQL before the page limit" do
    create_events(PER_PAGE + 5, title: "Filler")
    match = create_event("Quarterly Planning", starts_at: 60.days.from_now)

    get(calendar_events_path(source_id: @source.id, q: "quarterly"))

    assert_response(:success)
    assert_select("article h3", text: match.title, count: 1)
    assert_select("article", count: 1)
  end

  test "search matches location and description" do
    by_location = create_event("Alpha", location: "Riverside Studio")
    by_description = create_event("Beta", description: "Bring the riverside maps")
    create_event("Gamma")

    get(calendar_events_path(source_id: @source.id, q: "RIVERSIDE"))

    assert_select("article h3", text: by_location.title)
    assert_select("article h3", text: by_description.title)
    assert_select("article h3", text: "Gamma", count: 0)
  end

  test "search treats LIKE wildcards literally" do
    create_event("100% attendance")
    create_event("1000 attendees")

    get(calendar_events_path(source_id: @source.id, q: "100%"))

    assert_select("article", count: 1)
    assert_select("article h3", text: "100% attendance")
  end

  test "search matches the mapped title of contains and equals mappings for the right source" do
    other_source = calendar_sources(:ics_feed)
    EventMapping.create!(calendar_source: @source, pattern: "dsu", replacement: "Daily Standup", match_type: "contains")
    EventMapping.create!(pattern: "Retro", replacement: "Standup Retrospective", match_type: "equals")
    contains_match = create_event("Team DSU")
    equals_match = create_event("retro")
    CalendarEvent.create!(calendar_source: other_source, external_id: "other-dsu", title: "Other DSU", starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour)

    get(calendar_events_path(q: "standup"))

    assert_response(:success)
    assert_select("article h3", text: "Daily Standup")
    assert_select("article h3", text: "Standup Retrospective")
    assert_match(contains_match.title, response.body)
    assert_match(equals_match.title, response.body)
    refute_match("Other DSU", response.body)
  end

  test "lists one page of events with a next link that keeps the filters" do
    create_events(PER_PAGE + 3, title: "Session")

    get(calendar_events_path(source_id: @source.id, q: "session", show_excluded: true))

    assert_select("article", count: PER_PAGE)
    assert_select("#events-pagination a[rel=next][href=?]", calendar_events_path(source_id: @source.id, q: "session", show_excluded: true, page: 2))
    assert_select("#events-pagination a[rel=prev]", count: 0)
  end

  test "second page shows the remaining events and a previous link" do
    events = create_events(PER_PAGE + 3, title: "Session")

    get(calendar_events_path(source_id: @source.id, page: 2))

    assert_select("article", count: 3)
    events.last(3).each { |event| assert_select("turbo-frame##{ActionView::RecordIdentifier.dom_id(event)} article") }
    assert_select("#events-pagination a[rel=prev][href=?]", calendar_events_path(source_id: @source.id))
    assert_select("#events-pagination a[rel=next]", count: 0)
  end

  test "events with the same start time are not repeated across pages" do
    starts_at = 3.days.from_now.change(usec: 0)
    events = Array.new(PER_PAGE + 1) { |i| create_event("Same time #{i}", starts_at: starts_at) }

    get(calendar_events_path(source_id: @source.id))
    first_page = css_select("turbo-frame:has(> article)").pluck("id")
    get(calendar_events_path(source_id: @source.id, page: 2))
    second_page = css_select("turbo-frame:has(> article)").pluck("id")

    assert_equal(events.map { |event| ActionView::RecordIdentifier.dom_id(event) }.sort, (first_page + second_page).sort)
  end

  test "view toggles keep the active source and search" do
    get(calendar_events_path(source_id: @source.id, q: "planning"))

    assert_select("#events-view-toggles a[href=?]", calendar_events_path(source_id: @source.id, q: "planning", show_past: true))
    assert_select("#events-view-toggles a[href=?]", calendar_events_path(source_id: @source.id, q: "planning", show_excluded: true))
  end

  test "frame responses refresh the heading and view toggles for the new filters" do
    get(calendar_events_path(source_id: @source.id, q: "planning", show_past: true), headers: { "Turbo-Frame" => "events-list" })

    assert_response(:success)
    assert_select("turbo-stream[action=replace][target=events-list-heading]")
    assert_select("turbo-stream[action=replace][target=events-view-toggles]")
    assert_match(ERB::Util.html_escape(calendar_events_path(source_id: @source.id, q: "planning")), response.body)
  end

  test "invalid page numbers fall back to the first page" do
    create_event("Only event")

    get(calendar_events_path(source_id: @source.id, page: "-3"))

    assert_select("article", count: 1)
  end

  private

  def create_event(title, starts_at: 2.days.from_now, location: nil, description: nil)
    @event_counter = @event_counter.to_i + 1
    CalendarEvent.create!(
      calendar_source: @source,
      external_id: "paging-#{@event_counter}",
      title: title,
      location: location,
      description: description,
      starts_at: starts_at,
      ends_at: starts_at + 1.hour,
    )
  end

  def create_events(count, title:)
    Array.new(count) { |i| create_event("#{title} #{i}", starts_at: (i + 1).hours.from_now) }
  end
end
