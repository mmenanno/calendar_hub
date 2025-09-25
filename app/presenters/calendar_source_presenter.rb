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

  def auto_sync_status_text
    return I18n.t("ui.sources.auto_sync_disabled") unless source.auto_sync_enabled?

    if source.auto_syncable?
      if source.sync_due?
        I18n.t("ui.sources.auto_sync_due")
      else
        next_auto_sync = source.last_synced_at + source.sync_frequency_minutes.minutes
        "#{I18n.t("ui.sources.next_auto_sync")}: #{view.distance_of_time_in_words(Time.current, next_auto_sync)}"
      end
    else
      I18n.t("ui.sources.auto_sync_paused")
    end
  end

  def auto_sync_badge_class
    unless source.auto_sync_enabled?
      return "bg-slate-800 text-slate-400"
    end

    if source.auto_syncable?
      source.sync_due? ? "bg-yellow-500/10 text-yellow-300" : "bg-indigo-500/10 text-indigo-300"
    else
      "bg-slate-800 text-slate-400"
    end
  end

  def auto_sync_dot_class
    unless source.auto_sync_enabled?
      return "bg-slate-600"
    end

    if source.auto_syncable?
      source.sync_due? ? "bg-yellow-400" : "bg-indigo-400"
    else
      "bg-slate-600"
    end
  end

  def sync_frequency_text
    return "—" unless source.auto_sync_enabled?

    minutes = source.sync_frequency_minutes
    frequency_text = if minutes < 60
      I18n.t("ui.sources.every_n_minutes", count: minutes)
    else
      hours = minutes / 60
      I18n.t("ui.sources.every_n_hours", count: hours)
    end

    # Check if using default value (raw attribute is nil)
    if source.read_attribute(:sync_frequency_minutes).nil?
      "#{frequency_text} #{I18n.t("ui.sources.default_frequency_suffix")}"
    else
      frequency_text
    end
  end
end
