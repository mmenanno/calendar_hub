# frozen_string_literal: true

require "securerandom"

module CalendarHub
  class SyncService
    attr_reader :source, :apple_client, :translator, :adapter, :observer

    def initialize(source:, apple_client: AppleCalendar::Client.new, observer: nil, adapter: nil)
      @source = source
      @apple_client = apple_client
      @translator = CalendarHub::Translators::EventTranslator.new(source)
      @adapter = adapter || CalendarHub::Ingestion::GenericIcsAdapter.new(source)
      @observer = observer || NullObserver.new
    end

    def call
      raise Ingestion::Error, "No ingestion adapter configured" if adapter.nil?
      raise ArgumentError, "Calendar identifier is required" if source.calendar_identifier.blank?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fetched_events = adapter.fetch_events
      observer.start(total: fetched_events.size)
      processed_events = upsert_events(fetched_events)
      apply_counts = push_updates_to_apple(processed_events)
      cancel_counts = cancel_missing_events(fetched_events)
      source.mark_synced!(token: generate_sync_token, timestamp: Time.current)
      observer.finish(status: :success)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      ActiveSupport::Notifications.instrument(
        "calendar_hub.sync",
        source_id: source.id,
        fetched: fetched_events.size,
        upserts: apply_counts[:upserts],
        deletes: apply_counts[:deletes] + cancel_counts[:canceled],
        canceled: cancel_counts[:canceled],
        duration_ms: duration_ms,
      )
      Rails.logger.info(
        "[CalendarSync] source=#{source.id} fetched=#{fetched_events.size} upserts=#{apply_counts[:upserts]} " \
          "deletes=#{apply_counts[:deletes] + cancel_counts[:canceled]} canceled=#{cancel_counts[:canceled]} duration_ms=#{duration_ms}",
      )
      processed_events
    end

    private

    def initialize_adapter; end

    def upsert_events(fetched_events)
      fetched_events.map do |fetched|
        event = source.calendar_events.find_or_initialize_by(external_id: fetched.uid)
        event.assign_attributes(
          title: fetched.summary,
          description: fetched.description,
          location: fetched.location,
          starts_at: fetched.starts_at,
          ends_at: fetched.ends_at,
          status: fetched.status,
          source_updated_at: Time.current,
          data: (event.data || {}).merge(fetched.raw_properties || {}),
        )
        event.time_zone = source.time_zone
        event.save!
        event
      end
    end

    def push_updates_to_apple(events)
      upserts = 0
      deletes = 0
      events.sort_by { |e| e.starts_at.to_date }.chunk { |e| e.starts_at.to_date }.each do |_date, day_events|
        day_events.each do |event|
          if event.sync_exempt?
            apple_client.delete_event(calendar_identifier: source.calendar_identifier, uid: composite_uid_for(event))
            observer.delete_success(event)
            deletes += 1
          elsif event.cancelled?
            apple_client.delete_event(calendar_identifier: source.calendar_identifier, uid: composite_uid_for(event))
            observer.delete_success(event)
            deletes += 1
          else
            payload = translator.call(event)
            payload[:summary] = CalendarHub::NameMapper.apply(payload[:summary], source: source)
            payload[:url] = event_url_for(event)
            payload[:x_props] = { "X-CH-SOURCE" => source.name, "X-CH-SOURCE-ID" => source.id.to_s }
            apple_client.upsert_event(calendar_identifier: source.calendar_identifier, payload: payload)
            observer.upsert_success(event)
            upserts += 1
          end
          event.mark_synced!
        rescue StandardError => error
          Rails.logger.error("[CalendarSync] Failed to sync event #{event.external_id}: #{error.message}")
          observer.upsert_error(event, error)
        end
        # Small pause between day-batches to avoid server throttling
        sleep(0.05)
      end
      { upserts: upserts, deletes: deletes }
    end

    def cancel_missing_events(fetched_events)
      canceled = 0
      external_ids = fetched_events.map(&:uid)
      missing_events = source.calendar_events.where.not(external_id: external_ids)
      missing_events.find_each do |event|
        next if event.cancelled?

        event.update!(status: :cancelled, source_updated_at: Time.current)
        apple_client.delete_event(calendar_identifier: source.calendar_identifier, uid: composite_uid_for(event))
        observer.delete_success(event)
        canceled += 1
        event.mark_synced!
      rescue StandardError => error
        Rails.logger.warn("[CalendarSync] Failed to cancel event #{event.external_id}: #{error.message}")
        observer.delete_error(event, error)
      end
      { canceled: canceled }
    end

    def generate_sync_token
      SecureRandom.hex(16)
    end
  end
end

# Null observer that no-ops when not provided
module CalendarHub
  class NullObserver
    def start(total: 0); end
    def upsert_success(event); end
    def upsert_error(event, error); end
    def delete_success(event); end
    def delete_error(event, error); end
    def finish(status: :success, message: nil); end
  end
end

module CalendarHub
  class SyncService
    private

    def event_url_for(event)
      Rails.application.routes.url_helpers.calendar_event_url(event, **UrlOptions.for_links)
    rescue
      nil
    end

    def composite_uid_for(event)
      "ch-#{event.calendar_source_id}-#{event.external_id}"
    end
  end
end
