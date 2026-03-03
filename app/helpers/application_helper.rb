# frozen_string_literal: true

module ApplicationHelper
  def navigation_link_class(active: false)
    base = "rounded-lg px-3 py-2 font-medium transition"
    if active
      "#{base} bg-indigo-500 text-white shadow shadow-indigo-500/20"
    else
      "#{base} text-slate-300 hover:bg-slate-800 hover:text-white"
    end
  end

  def status_badge_class(status)
    case status.to_s
    when "cancelled"
      "text-rose-300"
    when "tentative"
      "text-amber-300"
    else
      "text-emerald-300"
    end
  end

  def input_class
    "w-full rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-sm text-slate-100 focus:border-indigo-400 focus:outline-none focus:ring-0"
  end

  def select_class
    [
      input_class,
      "appearance-none pr-8 bg-no-repeat",
      "bg-[length:18px_18px]",
      "bg-[right_0.6rem_center]",
      "bg-[url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 20 20\"><path fill=\"%23a5b4fc\" d=\"M5.5 7.5l4.5 4.5l4.5-4.5\" stroke=\"%23a5b4fc\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>')]",
    ].join(" ")
  end

  def flash_classes(type)
    base = "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3"
    case type.to_s
    when "notice", "success"
      "#{base} border-emerald-700 bg-emerald-500/10 text-emerald-200"
    when "alert", "error"
      "#{base} border-rose-800 bg-rose-950/40 text-rose-200"
    else
      "#{base} border-slate-800 bg-slate-900/70 text-slate-200"
    end
  end

  def calendar_hub_logo(type: :textless, **options)
    case type
    when :text
      image_tag("logos/text_logo.png", alt: "Calendar Hub", **options)
    when :textless
      image_tag("logos/textless_logo.png", alt: "Calendar Hub", **options)
    when :favicon
      image_tag("logos/favicon.png", alt: "Calendar Hub", **options)
    end
  end

  # Form field helpers to DRY up repetitive form patterns
  def form_field_label(form, field, text = nil, **options)
    text ||= field.to_s.humanize
    form.label(field, text, class: "mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400", **options)
  end

  def form_field_error(model, field)
    return if model.errors[field].none?

    content_tag(:p, model.errors[field].to_sentence, class: "mt-1 text-xs text-rose-300")
  end

  def form_field_hint(text)
    content_tag(:p, text, class: "mt-1 text-xs text-slate-400")
  end

  # Button style helpers
  def primary_button_class
    "cursor-pointer rounded-lg bg-indigo-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-400"
  end

  def secondary_button_class
    "cursor-pointer rounded-lg border border-slate-700 px-3 py-2 text-sm text-slate-200 transition hover:border-slate-500"
  end

  def danger_button_class
    "cursor-pointer rounded-lg border border-rose-700/40 px-3 py-2 text-sm text-rose-200 transition hover:border-rose-500"
  end

  def small_primary_button_class
    "cursor-pointer rounded-lg bg-indigo-500 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-indigo-400"
  end

  def small_danger_button_class
    "cursor-pointer rounded-lg bg-red-600 px-3 py-1 text-xs font-medium text-white hover:bg-red-500"
  end

  # Extract meaningful field changes from an audit record, filtering out
  # internal fields like updated_at, fingerprint, etc.
  AUDIT_SKIP_FIELDS = %w[id created_at updated_at fingerprint synced_at source_updated_at calendar_source_id external_id].freeze

  def audit_changed_fields(audit)
    from = audit.changes_from || {}
    to = audit.changes_to || {}
    all_keys = (from.keys + to.keys).uniq - AUDIT_SKIP_FIELDS
    all_keys.each_with_object({}) do |key, result|
      old_val = from[key]
      new_val = to[key]
      result[key] = [old_val, new_val] if old_val != new_val
    end
  end

  # Format sync attempt duration in a human-readable way
  def sync_attempt_duration(attempt)
    return "\u2014" unless attempt.started_at && attempt.finished_at

    seconds = (attempt.finished_at - attempt.started_at).to_f
    if seconds < 1
      "#{(seconds * 1000).round}ms"
    elsif seconds < 60
      "#{seconds.round(1)}s"
    else
      minutes = (seconds / 60).floor
      remaining = (seconds % 60).round
      "#{minutes}m #{remaining}s"
    end
  end

  # Format a duration given in milliseconds into a human-readable string.
  # < 1000 ms  -> "847 ms"
  # 1000..59999 -> "74.1 s"
  # >= 60000   -> "1m 14s"
  def format_duration_ms(ms)
    return "\u2014" if ms.nil?

    ms = ms.to_f
    if ms < 1000
      "#{ms.round} ms"
    elsif ms < 60_000
      "#{(ms / 1000.0).round(1)} s"
    else
      total_seconds = (ms / 1000.0).round
      minutes = total_seconds / 60
      seconds = total_seconds % 60
      "#{minutes}m #{seconds}s"
    end
  end
end
