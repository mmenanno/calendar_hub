# frozen_string_literal: true

require_relative "ingestion/generic_ics_adapter"

module CalendarHub
  module Ingestion
    class Error < StandardError
    end

    # The feed URL is not an absolute http(s) URL (after webcal normalization).
    class InvalidFeedURLError < Error
    end

    # DNS, TCP, TLS or timeout failure reaching the feed's server.
    class FeedConnectionError < Error
    end

    # The feed's server answered with a non-success HTTP status.
    class FeedHTTPError < Error
      attr_reader :status

      def initialize(message = nil, status: nil)
        super(message)
        @status = status
      end
    end

    # The response body exceeded HttpClient.max_body_bytes.
    class FeedTooLargeError < Error
    end

    # The whole fetch (all hops, headers and body) took longer than allowed.
    class FeedDeadlineError < Error
    end

    # CALENDAR_HUB_BLOCK_PRIVATE_FEEDS is on and the host is private/internal.
    class BlockedAddressError < Error
    end
  end
end
