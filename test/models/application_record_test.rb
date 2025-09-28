# frozen_string_literal: true

require "test_helper"

class ApplicationRecordTest < ActiveSupport::TestCase
  test "is primary abstract class" do
    assert_predicate(ApplicationRecord, :abstract_class?)
  end

  test "inherits from ActiveRecord::Base" do
    assert_operator(ApplicationRecord, :<, ActiveRecord::Base)
  end

  test "concrete models inherit from ApplicationRecord" do
    assert_operator(CalendarSource, :<, ApplicationRecord)
    assert_operator(CalendarEvent, :<, ApplicationRecord)
    assert_operator(FilterRule, :<, ApplicationRecord)
    assert_operator(EventMapping, :<, ApplicationRecord)
    assert_operator(SyncAttempt, :<, ApplicationRecord)
  end

  test "primary_abstract_class configuration is set" do
    assert_predicate(ApplicationRecord, :abstract_class?, "ApplicationRecord should be abstract")
    assert_equal(ApplicationRecord, CalendarSource.superclass)
  end
end
