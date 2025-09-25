# frozen_string_literal: true

class SyncStatusPresenter
  attr_reader :attempt

  def initialize(attempt)
    @attempt = attempt
  end

  def badge_class
    return "bg-emerald-500/10 text-emerald-300" if attempt.success?
    return "bg-indigo-500/10 text-indigo-300" if attempt.running?
    return "bg-rose-500/10 text-rose-300" if attempt.failed?

    "bg-slate-800 text-slate-300"
  end

  def dot_class
    return "bg-emerald-400" if attempt.success?
    return "bg-indigo-400" if attempt.running?
    return "bg-rose-400" if attempt.failed?

    "bg-slate-500"
  end

  def status_label
    attempt.status.to_s.capitalize
  end

  def started_ago
    return unless attempt.started_at

    ApplicationController.helpers.time_ago_in_words(attempt.started_at) + " ago"
  end

  def finished_ago
    return unless attempt.finished_at

    ApplicationController.helpers.time_ago_in_words(attempt.finished_at) + " ago"
  end
end
