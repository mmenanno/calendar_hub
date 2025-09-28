# frozen_string_literal: true

require "test_helper"

module CalendarHub
  class TranslatorsTest < ActiveSupport::TestCase
    test "for method returns EventTranslator class" do
      result = ::CalendarHub::Translators.for("any_provider")

      assert_equal(::CalendarHub::Translators::EventTranslator, result)
    end

    test "for method works with different provider arguments" do
      result1 = ::CalendarHub::Translators.for("google")
      result2 = ::CalendarHub::Translators.for("outlook")
      result3 = ::CalendarHub::Translators.for(nil)

      assert_equal(::CalendarHub::Translators::EventTranslator, result1)
      assert_equal(::CalendarHub::Translators::EventTranslator, result2)
      assert_equal(::CalendarHub::Translators::EventTranslator, result3)
    end

    test "register method exists and can be called" do
      assert_nothing_raised do
        ::CalendarHub::Translators.register("test")
      end

      assert_nothing_raised do
        ::CalendarHub::Translators.register("test1", "test2", "test3")
      end

      assert_nothing_raised do
        ::CalendarHub::Translators.register
      end
    end

    test "register method returns nil" do
      result1 = ::CalendarHub::Translators.register("test")
      result2 = ::CalendarHub::Translators.register("test1", "test2")
      result3 = ::CalendarHub::Translators.register

      assert_nil(result1)
      assert_nil(result2)
      assert_nil(result3)
    end
  end
end
