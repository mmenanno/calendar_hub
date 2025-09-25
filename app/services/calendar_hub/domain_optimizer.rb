# frozen_string_literal: true

require "uri"

module CalendarHub
  class DomainOptimizer
    class << self
      def group_sources_by_domain(sources)
        sources.group_by { |source| extract_apex_domain(source.ingestion_url) }
      end

      def extract_apex_domain(url)
        uri = URI.parse(url)
        return "unknown" unless uri.host

        host_parts = uri.host.split(".")

        if host_parts.length >= 2
          host_parts.last(2).join(".")
        else
          uri.host
        end
      rescue URI::InvalidURIError
        "unknown"
      end

      def optimize_sync_schedule(sources, window_minutes: 5)
        domain_groups = group_sources_by_domain(sources)
        schedule = {}

        domain_groups.each do |_domain, domain_sources|
          next_slot = Time.current

          domain_sources.sort_by(&:id).each do |source|
            schedule[source.id] = next_slot
            next_slot += window_minutes.minutes
          end
        end

        schedule
      end
    end
  end
end
