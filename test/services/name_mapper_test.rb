# frozen_string_literal: true

require "test_helper"

class NameMapperTest < ActiveSupport::TestCase
  test "compare? works for equals and contains with case insensitivity" do
    assert CalendarHub::NameMapper.send(:compare?, "Hello", "hello", case_sensitive: false, mode: :equals)
    assert CalendarHub::NameMapper.send(:compare?, "HelloWorld", "world", case_sensitive: false, mode: :contains)
    refute CalendarHub::NameMapper.send(:compare?, "Hello", "hello!", case_sensitive: false, mode: :equals)
  end
end
