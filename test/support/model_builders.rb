# frozen_string_literal: true

module ModelBuilders
  def build_event_attrs(**attrs)
    {
      external_id: SecureRandom.uuid,
      title: "Test Event",
      description: "Test description",
      location: "Test location",
      starts_at: 1.hour.from_now,
      ends_at: 2.hours.from_now,
      status: :confirmed,
      time_zone: "UTC",
      all_day: false,
      source_updated_at: Time.current,
      data: {},
    }.merge(attrs)
  end

  def build_event(calendar_source: nil, **attrs)
    calendar_source ||= calendar_sources(:provider)
    CalendarEvent.create!(build_event_attrs(calendar_source: calendar_source, **attrs))
  end

  def build_all_day_event_attrs(**attrs)
    date = Date.current
    build_event_attrs(
      starts_at: date.beginning_of_day,
      ends_at: (date + 1.day).beginning_of_day,
      all_day: true,
      **attrs,
    )
  end

  def build_all_day_event(calendar_source: nil, **attrs)
    calendar_source ||= calendar_sources(:provider)
    CalendarEvent.create!(build_all_day_event_attrs(calendar_source: calendar_source, **attrs))
  end

  def build_filter_rule_attrs(**attrs)
    {
      pattern: "Test Pattern",
      field_name: :title,
      match_type: :contains,
      case_sensitive: false,
      active: true,
      position: 0,
    }.merge(attrs)
  end

  def build_filter_rule(calendar_source: nil, **attrs)
    FilterRule.create!(build_filter_rule_attrs(calendar_source: calendar_source, **attrs))
  end

  def build_sync_attempt_attrs(**attrs)
    {
      status: :queued,
      total_events: 0,
      upserts: 0,
      deletes: 0,
      errors_count: 0,
    }.merge(attrs)
  end

  def build_sync_attempt(calendar_source: nil, **attrs)
    calendar_source ||= calendar_sources(:provider)
    SyncAttempt.create!(build_sync_attempt_attrs(calendar_source: calendar_source, **attrs))
  end

  def standard_event_times(date = Date.current)
    {
      starts_at: Time.zone.parse("#{date} 14:00:00"),
      ends_at: Time.zone.parse("#{date} 15:00:00"),
    }
  end

  def all_day_times(date = Date.current)
    {
      starts_at: date.beginning_of_day,
      ends_at: (date + 1.day).beginning_of_day,
      all_day: true,
    }
  end
end
