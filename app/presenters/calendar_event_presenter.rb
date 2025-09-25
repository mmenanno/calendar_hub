# frozen_string_literal: true

class CalendarEventPresenter
  attr_reader :event, :view

  def initialize(event, view_context)
    @event = event
    @view = view_context
  end

  # Returns the mapped title if a mapping rule applies; otherwise the original
  def title
    @mapped_title ||= CalendarHub::NameMapper.apply(event.title, source: event.calendar_source)
  end

  def original_title
    event.title
  end

  def title_mapped?
    title.to_s != original_title.to_s
  end

  def source_name
    event.calendar_source.name
  end

  def starts_at_long
    view.l(event.starts_at.in_time_zone(event.time_zone), format: :long)
  end

  def ends_at_long
    view.l(event.ends_at.in_time_zone(event.time_zone), format: :long)
  end

  # Provide a precise duration like "80 minutes" or "1 hour 20 minutes"
  def duration_precise
    total_seconds = (event.ends_at - event.starts_at).to_i
    total_minutes = (total_seconds / 60.0).round
    return "0 minutes" if total_minutes <= 0

    hours = total_minutes / 60
    minutes = total_minutes % 60

    parts = []
    parts << view.pluralize(hours, "hour") if hours.positive?
    parts << view.pluralize(minutes, "minute") if minutes.positive?
    parts.join(" ")
  end

  def last_synced_text
    event.synced_at ? "#{view.time_ago_in_words(event.synced_at)} ago" : I18n.t("ui.common.pending")
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
