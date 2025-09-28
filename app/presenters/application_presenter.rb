# frozen_string_literal: true

class ApplicationPresenter
  attr_reader :view

  def initialize(view_context)
    @view = view_context
  end

  private

  # Generate "X ago" text for timestamps
  def time_ago_text(timestamp, fallback = nil)
    return fallback unless timestamp

    "#{view.time_ago_in_words(timestamp)} ago"
  end

  # Generate badge CSS classes based on variant
  def badge_classes(variant)
    case variant.to_sym
    when :success
      "bg-emerald-500/10 text-emerald-300"
    when :warning
      "bg-yellow-500/10 text-yellow-300"
    when :danger
      "bg-rose-500/10 text-rose-300"
    when :info
      "bg-indigo-500/10 text-indigo-300"
    else
      "bg-slate-800 text-slate-400"
    end
  end

  # Generate dot CSS classes based on variant
  def dot_classes(variant)
    case variant.to_sym
    when :success
      "bg-emerald-400"
    when :warning
      "bg-yellow-400"
    when :danger
      "bg-rose-400"
    when :info
      "bg-indigo-400"
    else
      "bg-slate-600"
    end
  end

  # Helper to return a value or default dash
  def presence_or_dash(value)
    value.presence || "—"
  end
end
