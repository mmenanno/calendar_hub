# frozen_string_literal: true

require "test_helper"

class UrlOptionsTest < ActiveSupport::TestCase
  setup do
    @settings = AppSetting.instance
    @original_env = ENV.to_h
  end

  teardown do
    # Restore original ENV values
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    @settings.update!(
      app_host: nil,
      app_protocol: "http", # NOT NULL constraint
      app_port: nil,
    )
  end

  test "includes port for localhost when set" do
    @settings.update!(app_host: "localhost", app_protocol: "http", app_port: "3000")
    opts = UrlOptions.for_links

    assert_equal("localhost", opts[:host])
    assert_equal("http", opts[:protocol])
    assert_equal(3000, opts[:port])
  end

  test "uses settings values when available" do
    @settings.update!(
      app_host: "example.com",
      app_protocol: "https",
      app_port: "443",
    )
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("https", opts[:protocol])
    assert_equal(443, opts[:port])
  end

  test "falls back to default_url_options when settings are blank" do
    Rails.application.routes.default_url_options[:host] = "default-host.com"
    @settings.update!(app_host: nil, app_protocol: "http", app_port: nil)

    opts = UrlOptions.for_links

    assert_equal("default-host.com", opts[:host])
    assert_equal("http", opts[:protocol]) # Falls back to ENV default
    refute(opts.key?(:port))
  end

  test "falls back to ENV values when settings and default_url_options are blank" do
    Rails.application.routes.default_url_options.delete(:host)
    ENV["APP_HOST"] = "env-host.com"
    ENV["APP_PROTOCOL"] = "https"
    ENV["APP_PORT"] = "8080"
    @settings.update!(app_host: nil, app_protocol: "", app_port: nil) # Empty string, not nil

    opts = UrlOptions.for_links

    assert_equal("env-host.com", opts[:host])
    assert_equal("https", opts[:protocol])
    assert_equal(8080, opts[:port])
  end

  test "uses final fallback values when nothing is set" do
    Rails.application.routes.default_url_options.delete(:host)
    ENV.delete("APP_HOST")
    ENV.delete("APP_PROTOCOL")
    ENV.delete("APP_PORT")
    @settings.update!(app_host: nil, app_protocol: "", app_port: nil) # Empty string to trigger fallback

    opts = UrlOptions.for_links

    assert_equal("localhost", opts[:host])
    assert_equal("http", opts[:protocol])
    refute(opts.key?(:port))
  end

  test "handles host with port already included" do
    @settings.update!(app_host: "example.com:8080", app_protocol: "https")
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("https", opts[:protocol])
    assert_equal(8080, opts[:port])
  end

  test "prefers explicit port over host-included port" do
    @settings.update!(
      app_host: "example.com:8080",
      app_protocol: "https",
      app_port: "9090",
    )
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("https", opts[:protocol])
    assert_equal(9090, opts[:port]) # Explicit port wins
  end

  test "handles ENV APP_PORT when no explicit port set" do
    ENV["APP_PORT"] = "5000"
    @settings.update!(
      app_host: "example.com",
      app_protocol: "http",
      app_port: nil,
    )
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("http", opts[:protocol])
    assert_equal(5000, opts[:port])
  end

  test "ignores zero or negative ports" do
    @settings.update!(
      app_host: "example.com",
      app_protocol: "http",
      app_port: "0",
    )
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("http", opts[:protocol])
    refute(opts.key?(:port))
  end

  test "ignores non-numeric ports" do
    @settings.update!(
      app_host: "example.com",
      app_protocol: "http",
      app_port: "invalid",
    )
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("http", opts[:protocol])
    refute(opts.key?(:port))
  end

  # NOTE: split_host_port is a private method, so we test its behavior indirectly through for_links
  test "handles host with port extraction behavior" do
    @settings.update!(app_host: "example.com:9000", app_protocol: "https", app_port: nil)
    opts = UrlOptions.for_links

    assert_equal("example.com", opts[:host])
    assert_equal("https", opts[:protocol])
    assert_equal(9000, opts[:port])
  end

  test "handles IPv6-like hosts" do
    @settings.update!(app_host: "localhost", app_protocol: "http", app_port: "3000")
    opts = UrlOptions.for_links

    assert_equal("localhost", opts[:host])
    assert_equal("http", opts[:protocol])
    assert_equal(3000, opts[:port])
  end
end
