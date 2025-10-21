# frozen_string_literal: true

require_relative "boot"

require "rails/all"
require_relative "../app/services/calendar_hub/key_store"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CalendarHub
  class Application < Rails::Application
    class << self
      def generate_or_load_secret_key_base
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
    config.load_defaults(8.0)

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

    # Auto-generate secret_key_base for distributed deployments
    config.secret_key_base = Rails.application.credentials.secret_key_base ||
      ENV["SECRET_KEY_BASE"] ||
      generate_or_load_secret_key_base
  end
end
