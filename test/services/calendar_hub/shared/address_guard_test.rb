# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module Shared
    class AddressGuardTest < ActiveSupport::TestCase
      test "blocks internal addresses" do
        [
          "127.0.0.1",
          "127.8.9.10",
          "10.0.0.1",
          "172.16.5.4",
          "172.31.255.255",
          "192.168.1.1",
          "169.254.169.254",
          "100.64.0.1",
          "100.127.255.254",
          "0.0.0.0",
          "224.0.0.1",
          "255.255.255.255",
          "::",
          "::1",
          "fc00::1",
          "fd12:3456::1",
          "fe80::1",
          "fe80::1%en0",
          "ff02::1",
          "::ffff:127.0.0.1",
          "::ffff:10.0.0.1",
          "::ffff:169.254.169.254",
        ].each do |address|
          assert(AddressGuard.blocked?(address), "expected #{address} to be blocked")
        end
      end

      test "allows public addresses" do
        ["93.184.216.34", "8.8.8.8", "172.32.0.1", "100.128.0.1", "2606:2800:220:1:248:1893:25c8:1946", "::ffff:8.8.8.8"].each do |address|
          refute(AddressGuard.blocked?(address), "expected #{address} to be allowed")
        end
      end

      test "treats unparsable addresses as blocked" do
        assert(AddressGuard.blocked?("not-an-ip"))
      end

      test "validated_address! returns the first address of a public host" do
        AddressGuard.stubs(:resolve).with("example.com", 5).returns(["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"])

        assert_equal("93.184.216.34", AddressGuard.validated_address!("example.com", timeout: 5))
      end

      test "validated_address! resolves literal IPs to themselves" do
        assert_equal("8.8.8.8", AddressGuard.validated_address!("8.8.8.8"))
        assert_raises(CalendarHub::Ingestion::BlockedAddressError) { AddressGuard.validated_address!("127.0.0.1") }
        assert_raises(CalendarHub::Ingestion::BlockedAddressError) { AddressGuard.validated_address!("::1") }
      end

      test "validated_address! raises a connection error when the host does not resolve" do
        Addrinfo.stubs(:getaddrinfo).raises(SocketError, "getaddrinfo: nodename nor servname provided")

        assert_raises(CalendarHub::Ingestion::FeedConnectionError) { AddressGuard.validated_address!("nope.invalid") }
      end
    end
  end
end
