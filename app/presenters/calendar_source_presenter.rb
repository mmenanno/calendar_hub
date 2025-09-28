# frozen_string_literal: true

class CalendarSourcePresenter < ApplicationPresenter
  attr_reader :source

  def initialize(source, view_context)
    super(view_context)
    @source = source
  end

  delegate :name, to: :source

  def calendar_identifier
    presence_or_dash(source.calendar_identifier)
  end

  def last_synced_text
    time_ago_text(source.last_synced_at, I18n.t("common.states.never"))
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
    badge_classes(active_badge_variant)
  end

  def active_dot_class
    dot_classes(active_badge_variant)
  end

  def active_label
    return I18n.t("common.states.archived") if deleted?

    source.active? ? I18n.t("common.states.active") : I18n.t("common.states.paused")
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
    badge_classes(auto_sync_badge_variant)
  end

  def auto_sync_dot_class
    dot_classes(auto_sync_badge_variant)
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

  private

  def active_badge_variant
    return :danger if deleted?

    source.active? ? :success : :default
  end

  def auto_sync_badge_variant
    return :default unless source.auto_sync_enabled?

    if source.auto_syncable?
      source.sync_due? ? :warning : :info
    else
      :default
    end
  end
end
