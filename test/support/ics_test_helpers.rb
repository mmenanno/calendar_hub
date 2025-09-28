# frozen_string_literal: true

# ICSTestHelpers provides utilities for creating ICS content and event objects in tests
#
# This module helps DRY up test code by providing reusable methods for creating:
# - ICS content strings for parser testing
# - CalendarHub::ICS::Event objects for service testing
# - Apple Calendar payload objects for client testing
#
# Examples:
#
#   # Create simple ICS content
#   ics_content = build_ics_content(build_simple_event(uid: "test-123", summary: "Meeting"))
#
#   # Create multiple events
#   events = build_event_series(count: 3, base_uid: "meeting")
#   ics_content = build_ics_content(events)
#
#   # Create CalendarHub::ICS::Event objects
#   event = build_ics_event(uid: "test", summary: "Test Event")
#
#   # Create Apple Calendar payloads
#   payload = build_apple_payload(uid: "test", summary: "Test Event", all_day: true)
#
#   # Use convenience methods for common patterns
#   all_day = build_all_day_event(uid: "vacation", summary: "Vacation Day")
#   cancelled = build_cancelled_event(uid: "meeting", summary: "Cancelled Meeting")
#   provider = build_provider_event(uid: "session", summary: "Therapy Session")
#
module ICSTestHelpers
  def build_ics_content(events = [], prodid: "-//CalendarHub//Test//EN")
    events = [events] unless events.is_a?(Array)

    content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:#{prodid}
      CALSCALE:GREGORIAN
    ICS

    events.each do |event|
      content += build_vevent_content(event)
    end

    content += "END:VCALENDAR\n"
    content
  end

  def build_vevent_content(event)
    event = normalize_event_data(event)

    vevent = "BEGIN:VEVENT\n"
    vevent += "UID:#{event[:uid]}\n"
    vevent += "DTSTAMP:#{event[:dtstamp] || default_dtstamp}\n"

    if event[:all_day]
      vevent += "DTSTART;VALUE=DATE:#{format_date_only(event[:starts_at])}\n"
      vevent += "DTEND;VALUE=DATE:#{format_date_only(event[:ends_at])}\n"
    elsif event[:timezone]
      vevent += "DTSTART;TZID=#{event[:timezone]}:#{format_local_datetime(event[:starts_at])}\n"
      vevent += "DTEND;TZID=#{event[:timezone]}:#{format_local_datetime(event[:ends_at])}\n"
    else
      vevent += "DTSTART:#{format_utc_datetime(event[:starts_at])}\n"
      vevent += "DTEND:#{format_utc_datetime(event[:ends_at])}\n"
    end

    vevent += "SUMMARY:#{escape_ics_value(event[:summary])}\n" if event[:summary]
    vevent += "DESCRIPTION:#{escape_ics_value(event[:description])}\n" if event[:description]
    vevent += "LOCATION:#{escape_ics_value(event[:location])}\n" if event[:location]
    vevent += "STATUS:#{event[:status].upcase}\n" if event[:status]
    vevent += "URL:#{escape_ics_value(event[:url])}\n" if event[:url]

    event[:custom_properties]&.each do |key, value|
      vevent += "#{key.upcase}:#{escape_ics_value(value)}\n"
    end

    vevent += "END:VEVENT\n"
    vevent
  end

  def build_ics_event(uid:, summary: "Test Event", **options)
    defaults = {
      description: nil,
      location: nil,
      starts_at: Time.zone.parse("2025-01-01 10:00"),
      ends_at: Time.zone.parse("2025-01-01 11:00"),
      status: "confirmed",
      time_zone: "UTC",
      all_day: false,
      raw_properties: {},
    }

    attributes = defaults.merge(options).merge(uid: uid, summary: summary)
    ::CalendarHub::ICS::Event.new(**attributes)
  end

  def build_apple_payload(uid:, summary: "Test Event", **options)
    defaults = {
      description: "",
      location: "",
      starts_at: Time.utc(2025, 1, 1, 10, 0, 0),
      ends_at: Time.utc(2025, 1, 1, 11, 0, 0),
      all_day: false,
      url: "",
      x_props: {},
    }

    defaults.merge(options).merge(uid: uid, summary: summary)
  end

  def build_simple_event(uid: "test-#{SecureRandom.hex(4)}", summary: "Simple Event", **options)
    defaults = {
      starts_at: Time.zone.parse("2025-01-01 10:00"),
      ends_at: Time.zone.parse("2025-01-01 11:00"),
    }
    defaults.merge(options).merge(uid: uid, summary: summary)
  end

  def build_all_day_event(uid: "allday-#{SecureRandom.hex(4)}", summary: "All Day Event", **options)
    defaults = {
      starts_at: Time.zone.parse("2025-01-01"),
      ends_at: Time.zone.parse("2025-01-02"),
      all_day: true,
    }
    defaults.merge(options).merge(uid: uid, summary: summary)
  end

  def build_cancelled_event(uid: "cancelled-#{SecureRandom.hex(4)}", summary: "Cancelled Event")
    {
      uid: uid,
      summary: summary,
      starts_at: Time.zone.parse("2025-01-01 14:00"),
      ends_at: Time.zone.parse("2025-01-01 15:00"),
      status: "cancelled",
    }
  end

  def build_recurring_event(uid: "recurring-#{SecureRandom.hex(4)}", summary: "Recurring Event")
    {
      uid: uid,
      summary: summary,
      starts_at: Time.zone.parse("2025-01-01 09:00"),
      ends_at: Time.zone.parse("2025-01-01 10:00"),
      custom_properties: {
        "RRULE" => "FREQ=WEEKLY;BYDAY=MO,WE,FR",
      },
    }
  end

  def build_provider_event(uid: "prov-#{SecureRandom.hex(4)}", summary: "Provider Session")
    {
      uid: uid,
      summary: summary,
      description: "Session with client",
      location: "Studio A",
      starts_at: Time.zone.parse("2025-01-01 14:00"),
      ends_at: Time.zone.parse("2025-01-01 15:00"),
      timezone: "America/Toronto",
      custom_properties: {
        "X-PROVIDER-PRACTITIONER" => "Dr. Smith",
        "X-PROVIDER-CLIENT" => "John Doe",
        "X-PROVIDER-TREATMENT" => "Massage Therapy",
      },
    }
  end

  def build_event_series(count: 3, base_uid: "series", base_summary: "Series Event")
    (1..count).map do |i|
      {
        uid: "#{base_uid}-#{i}",
        summary: "#{base_summary} #{i}",
        starts_at: Time.zone.parse("2025-01-01 10:00") + (i - 1).hours,
        ends_at: Time.zone.parse("2025-01-01 11:00") + (i - 1).hours,
      }
    end
  end

  private

  def normalize_event_data(event)
    if event.is_a?(Hash)
      event
    else
      {
        uid: event.uid,
        summary: event.summary,
        description: event.description,
        location: event.location,
        starts_at: event.starts_at,
        ends_at: event.ends_at,
        status: event.status,
        all_day: event.all_day,
        timezone: event.time_zone,
        custom_properties: event.respond_to?(:raw_properties) ? event.raw_properties : {},
      }
    end
  end

  def default_dtstamp
    Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  def format_date_only(time)
    time.strftime("%Y%m%d")
  end

  def format_local_datetime(time)
    time.strftime("%Y%m%dT%H%M%S")
  end

  def format_utc_datetime(time)
    time.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  def escape_ics_value(value)
    return "" if value.nil?

    value.to_s.gsub(/\\|;|,|\n/, "\\\\" => "\\\\", ";" => "\\;", "," => "\\,", "\n" => "\\n")
  end
end
