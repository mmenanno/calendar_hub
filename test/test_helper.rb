# frozen_string_literal: true

require "simplecov"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocha/minitest"

WebMock.disable_net_connect!(allow_localhost: true)
ActiveJob::Base.queue_adapter = :test

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |_worker|
      SimpleCov.command_name("Job::#{Process.pid}") if const_defined?(:SimpleCov)
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include ActiveJob::TestHelper
  end
end
