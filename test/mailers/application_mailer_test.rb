# frozen_string_literal: true

require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  test "default from address is set" do
    assert_equal("from@example.com", ApplicationMailer.default[:from])
  end

  test "default layout is mailer" do
    # Check that the layout is set in the class definition
    # The layout is accessible via the class method
    assert_equal("mailer", ApplicationMailer._layout.to_s)
  end

  test "inherits from ActionMailer::Base" do
    assert_operator(ApplicationMailer, :<, ActionMailer::Base)
  end
end
