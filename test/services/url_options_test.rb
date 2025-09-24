# frozen_string_literal: true

require "test_helper"

class UrlOptionsTest < ActiveSupport::TestCase
  test "includes port for localhost when set" do
    settings = AppSetting.instance
    settings.update!(app_host: "localhost", app_protocol: "http", app_port: 3000)
    opts = UrlOptions.for_links

    assert_equal "localhost", opts[:host]
    assert_equal "http", opts[:protocol]
    assert_equal 3000, opts[:port]
  end
end
