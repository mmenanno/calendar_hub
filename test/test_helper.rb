# frozen_string_literal: true

require "simplecov"
SimpleCov.start("rails")

ENV["RAILS_ENV"] ||= "test"
# Keep tests away from storage/key_store.json; each parallel worker gets its
# own file (see parallelize_setup) so a key rotated in one worker is never
# picked up by another.
ENV["CALENDAR_HUB_KEY_STORE_PATH"] = File.expand_path("../tmp/test_key_store.json", __dir__)
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

    parallelize_setup do |worker|
      SimpleCov.command_name("Job::#{Process.pid}") if const_defined?(:SimpleCov)
      ENV["CALENDAR_HUB_KEY_STORE_PATH"] = File.expand_path("../tmp/test_key_store_#{worker}.json", __dir__)
      CalendarHub::CredentialEncryption.reset!
    end

    fixtures :all

    setup do
      AppSetting.reset_instance!
    end
  end
end
