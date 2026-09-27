# frozen_string_literal: true

# Sample Insights SQL events: a calendar sync runs thousands of queries.
# Events from the same web request are kept or dropped together.
# Override with HONEYBADGER_SQL_EVENT_SAMPLE_RATE (0-100, default 5).
Rails.application.config.after_initialize do
  sql_sample_rate = Integer(ENV.fetch("HONEYBADGER_SQL_EVENT_SAMPLE_RATE", 5))

  Honeybadger.configure do |config|
    config.before_event do |event|
      event[:_hb] = { sample_rate: sql_sample_rate } if event.event_type == "sql.active_record"
    end
  end
end
