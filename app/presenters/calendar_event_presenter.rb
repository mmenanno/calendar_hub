# frozen_string_literal: true

class CalendarEventPresenter
  attr_reader :event, :view

  def initialize(event, view_context)
    @event = event
    @view = view_context
  end

  delegate :title, to: :event

  def source_name
    event.calendar_source.name
  end

  def starts_at_long
    view.l(event.starts_at.in_time_zone(event.time_zone), format: :long)
  end

  def ends_at_long
    view.l(event.ends_at.in_time_zone(event.time_zone), format: :long)
  end

  def duration_human
    view.distance_of_time_in_words(event.starts_at, event.ends_at)
  end

  def last_synced_text
    event.synced_at ? "#{view.time_ago_in_words(event.synced_at)} ago" : "Pending"
  end

  def location
    event.location.presence || "—"
  end

  delegate :status, to: :event

  def status_badge_class
    view.status_badge_class(event.status)
  end

  def excluded?
    event.sync_exempt?
  end
end
