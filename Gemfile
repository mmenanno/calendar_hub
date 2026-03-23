# frozen_string_literal: true

source "https://rubygems.org"

# Core framework and platform integrations
gem "importmap-rails"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rails", "~> 8.1"
gem "sqlite3", ">= 2.1"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "turbo-rails"

# Background processing, caching, and realtime
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"

# Deployment and server
gem "thruster", require: false

# Performance
gem "bootsnap", require: false

# Diagnostics, tooling, and quality
group :development, :test, :ci do
  gem "brakeman", require: false
  gem "debug", platforms: [:mri], require: "debug/prelude"
  gem "erb_lint", require: false
  gem "rubocop-mmenanno-rails", require: false
  gem "toys", "~> 0.21.0"
end

# System testing and HTTP mocking
group :test, :ci do
  gem "mocha"
  gem "simplecov", require: false
  gem "webmock"
end

# Jobs and maintenance
gem "activejob-uniqueness"
gem "maintenance_tasks"
gem "mission_control-jobs"

# Networking and parsing
gem "faraday"
gem "nokogiri"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: [:windows, :jruby]

gem "honeybadger", "~> 6.5"
