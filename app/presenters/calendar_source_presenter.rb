# frozen_string_literal: true

class CalendarSourcePresenter
  attr_reader :source, :view

  def initialize(source, view_context)
    @source = source
    @view = view_context
  end

  delegate :name, to: :source

  def calendar_identifier
    source.calendar_identifier.presence || "—"
  end

  def last_synced_text
    source.last_synced_at ? "#{view.time_ago_in_words(source.last_synced_at)} ago" : I18n.t("ui.common.never")
  end

  def pending_count
    source.pending_events_count
  end

  def next_sync_text
    if source.within_sync_window?
      I18n.t("ui.sources.now")
    else
      time = source.next_sync_time
      "#{view.l(time, format: :short)} (#{view.distance_of_time_in_words(Time.current, time)})"
    end
  end

  def active_badge_class
    if deleted?
      "bg-rose-500/10 text-rose-300"
    else
      source.active? ? "bg-emerald-500/10 text-emerald-300" : "bg-slate-800 text-slate-400"
    end
  end

  def active_dot_class
    if deleted?
      "bg-rose-400"
    else
      source.active? ? "bg-emerald-400" : "bg-slate-600"
    end
  end

  def active_label
    return I18n.t("ui.sources.archived") if deleted?

    source.active? ? I18n.t("ui.sources.active") : I18n.t("ui.sources.paused")
  end

  def deleted?
    source.deleted_at.present?
  end
end
