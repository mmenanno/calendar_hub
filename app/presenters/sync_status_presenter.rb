# frozen_string_literal: true

class SyncStatusPresenter < ApplicationPresenter
  attr_reader :attempt

  def initialize(attempt, view_context)
    super(view_context)
    @attempt = attempt
  end

  def badge_class
    variant = badge_variant
    return "bg-slate-800 text-slate-300" if variant == :default

    badge_classes(variant)
  end

  def dot_class
    variant = badge_variant
    return "bg-slate-500" if variant == :default

    dot_classes(variant)
  end

  def status_label
    attempt.status.to_s.capitalize
  end

  def started_ago
    time_ago_text(attempt.started_at)
  end

  def finished_ago
    time_ago_text(attempt.finished_at)
  end

  private

  def badge_variant
    return :success if attempt.success?
    return :info if attempt.running?
    return :danger if attempt.failed?

    :default
  end
end
