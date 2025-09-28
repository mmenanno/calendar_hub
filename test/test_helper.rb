# frozen_string_literal: true

require "simplecov"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocha/minitest"

Rails.root.glob("test/support/**/*.rb").each { |f| require f }

WebMock.disable_net_connect!(allow_localhost: true)
ActiveJob::Base.queue_adapter = :test

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    parallelize_setup do |_worker|
      SimpleCov.command_name("Job::#{Process.pid}") if const_defined?(:SimpleCov)
    end

    fixtures :all
  end
end
