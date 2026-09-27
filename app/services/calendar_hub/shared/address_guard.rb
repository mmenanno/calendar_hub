# frozen_string_literal: true

require "ipaddr"
require "socket"

module CalendarHub
  module Shared
    # Opt-in SSRF guard (CALENDAR_HUB_BLOCK_PRIVATE_FEEDS): resolves a feed
    # host and refuses it when any of its addresses is loopback, private,
    # link-local (incl. cloud metadata), unspecified, multicast, CGNAT or an
    # IPv4-mapped IPv6 form of those. HttpClient then pins the connection to
    # the returned address so DNS can't change between check and connect.
    module AddressGuard
      BLOCKED_RANGES = [
        "0.0.0.0/8",       # "this network", incl. unspecified 0.0.0.0
        "10.0.0.0/8",      # RFC 1918
        "100.64.0.0/10",   # carrier-grade NAT (RFC 6598)
        "127.0.0.0/8",     # loopback
        "169.254.0.0/16",  # link-local, incl. cloud metadata (169.254.169.254)
        "172.16.0.0/12",   # RFC 1918
        "192.168.0.0/16",  # RFC 1918
        "224.0.0.0/4",     # multicast
        "240.0.0.0/4",     # reserved, incl. broadcast
        "::/128",          # unspecified
        "::1/128",         # loopback
        "fc00::/7",        # unique local
        "fe80::/10",       # link-local
        "ff00::/8",        # multicast
      ].map { |range| IPAddr.new(range) }.freeze

      class << self
        # Returns the address to connect to, or raises BlockedAddressError
        # (any blocked address taints the host) / FeedConnectionError (the
        # host doesn't resolve).
        def validated_address!(host, timeout: nil)
          addresses = resolve(host, timeout)
          raise CalendarHub::Ingestion::FeedConnectionError, "Could not resolve the feed host" if addresses.empty?
          raise CalendarHub::Ingestion::BlockedAddressError, "Feed host resolves to a private or internal address" if addresses.any? { |address| blocked?(address) }

          addresses.first
        end

        def blocked?(address)
          ip = IPAddr.new(address.to_s).native
          BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
        rescue IPAddr::Error
          true
        end

        # Literal IP hosts resolve to themselves.
        def resolve(host, timeout)
          Addrinfo.getaddrinfo(host.to_s, nil, nil, :STREAM, timeout: timeout).map(&:ip_address).uniq
        rescue SocketError, IO::TimeoutError
          []
        end
      end
    end
  end
end
