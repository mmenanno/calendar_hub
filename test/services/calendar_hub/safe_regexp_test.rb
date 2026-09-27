# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class SafeRegexpTest < ActiveSupport::TestCase
    test "compile returns nil for an invalid pattern" do
      assert_nil(SafeRegexp.compile("(unclosed", case_sensitive: true))
    end

    test "gsub leaves text unchanged when the pattern did not compile" do
      assert_equal("Dentist", SafeRegexp.gsub(nil, "Dentist", "X"))
    end

    test "a pathological pattern times out as a non-match" do
      regex = SafeRegexp.compile("^(a|a)*\\1?$", case_sensitive: true)

      refute(SafeRegexp.match?(regex, "#{"a" * 40}!"))
    end

    test "a process-wide regex timeout is configured as a backstop" do
      assert_operator(Regexp.timeout.to_f, :>, 0)
    end
  end
end
