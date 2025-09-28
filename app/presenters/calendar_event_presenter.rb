# frozen_string_literal: true

class CalendarEventPresenter < ApplicationPresenter
  attr_reader :event

  def initialize(event, view_context)
    super(view_context)
    @event = event
  end

  # Returns the mapped title if a mapping rule applies; otherwise the original
  def title
    @mapped_title ||= begin
      cache_key = "mapped_title/#{event.id}/#{event.updated_at.to_i}"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        CalendarHub::NameMapper.apply(event.title, source: event.calendar_source)
      end
    end
  end

  def original_title
    event.title
  end

  def title_mapped?
    title.to_s != original_title.to_s
  end

  def source_name
    source = event.calendar_source
    return "Unknown Source" unless source

    if source.deleted_at?
      "#{source.name} (archived)"
    else
      source.name
    end
  end

  def starts_at_long
    if event.all_day?
      view.l(event.starts_at.in_time_zone(event.time_zone).to_date, format: :long)
    else
      view.l(event.starts_at.in_time_zone(event.time_zone), format: :long)
    end
  end

  def ends_at_long
    if event.all_day?
      view.l(event.ends_at.in_time_zone(event.time_zone).to_date, format: :long)
    else
      view.l(event.ends_at.in_time_zone(event.time_zone), format: :long)
    end
  end

  # Provide a precise duration like "80 minutes" or "1 hour 20 minutes"
  def duration_precise
    if event.all_day?
      days = event.duration_days
      return "All day" if days <= 1

      view.pluralize(days, "day")
    else
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
  end

  def last_synced_text
    time_ago_text(event.synced_at, I18n.t("common.states.pending"))
  end

  def location
    presence_or_dash(event.location)
  end

  delegate :status, to: :event

  def status_badge_class
    view.status_badge_class(event.status)
  end

  def excluded?
    event.sync_exempt?
  end

  def time_display
    if event.all_day?
      if event.duration_days <= 1
        "All day"
      else
        "#{starts_at_long} - #{ends_at_long}"
      end
    else
      starts_at_long.to_s
    end
  end
end
