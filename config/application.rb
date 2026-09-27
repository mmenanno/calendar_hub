# frozen_string_literal: true

require_relative "boot"

require "rails"
# Only load the frameworks the app actually uses (no Active Storage, Action
# Mailer, Action Mailbox or Action Text).
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CalendarHub
  class Application < Rails::Application
    class << self
      def generate_or_load_secret_key_base
        require_relative "../app/services/calendar_hub/key_store"

        store = CalendarHub::KeyStore.instance
        existing = store.secret_key_base
        return existing if existing.present?

        require "securerandom"
        new_secret = SecureRandom.hex(64)
        store.write_secret_key_base!(new_secret)
        new_secret
      end
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults(8.1)

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: ["assets", "tasks"])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "UTC"
    config.active_job.queue_adapter = :solid_queue

    # Auto-generate and persist secret_key_base (storage/key_store.json) for
    # self-hosted deployments. Skipped in the test env and during asset
    # precompilation (SECRET_KEY_BASE_DUMMY), where Rails falls back to its
    # generated local secret. This keeps a secret from being baked into the
    # Docker image at build time, and lets SimpleCov measure KeyStore (the
    # test runner loads this file before test_helper starts coverage).
    unless Rails.env.test? || ENV["SECRET_KEY_BASE_DUMMY"].present?
      config.secret_key_base = Rails.application.credentials.secret_key_base ||
        ENV["SECRET_KEY_BASE"] ||
        generate_or_load_secret_key_base
    end
  end
end
