# frozen_string_literal: true

class SyncMetric < ApplicationRecord
  belongs_to :calendar_source

  validates :occurred_at, presence: true

  scope :for_source, ->(source_id) { where(calendar_source_id: source_id) }
  scope :last_7_days, -> { where(occurred_at: 7.days.ago.beginning_of_day..) }

  def self.daily_trend(source_id, days: 7)
    start_date = days.days.ago.to_date
    end_date = Date.current

    # Query aggregated daily metrics
    daily_data = for_source(source_id)
      .where(occurred_at: start_date.beginning_of_day..)
      .group("date(occurred_at)")
      .pluck(
        Arel.sql("date(occurred_at)"),
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(upserts_count)"),
        Arel.sql("SUM(deletes_count)"),
        Arel.sql("SUM(errors_count)"),
        Arel.sql("AVG(duration_ms)"),
      )

    # Fall back to sync_attempts if no metrics have been recorded yet
    if daily_data.empty?
      daily_data = SyncAttempt
        .where(calendar_source_id: source_id, status: [:success, :failed])
        .where(finished_at: start_date.beginning_of_day..)
        .group("date(finished_at)")
        .pluck(
          Arel.sql("date(finished_at)"),
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(upserts)"),
          Arel.sql("SUM(deletes)"),
          Arel.sql("SUM(errors_count)"),
          Arel.sql("AVG(CASE WHEN started_at IS NOT NULL AND finished_at IS NOT NULL THEN (julianday(finished_at) - julianday(started_at)) * 86400000 ELSE 0 END)"),
        )
    end

    # Build a hash keyed by date string
    data_by_date = daily_data.each_with_object({}) do |row, hash|
      hash[row[0].to_s] = {
        date: row[0].to_s,
        syncs: row[1].to_i,
        upserts: row[2].to_i,
        deletes: row[3].to_i,
        errors: row[4].to_i,
        avg_duration_ms: row[5].to_i,
      }
    end

    # Fill in missing days with zeros
    (start_date..end_date).map do |date|
      date_str = date.to_s
      data_by_date[date_str] || {
        date: date_str,
        syncs: 0,
        upserts: 0,
        deletes: 0,
        errors: 0,
        avg_duration_ms: 0,
      }
    end
  end
end
