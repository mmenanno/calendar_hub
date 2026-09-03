# frozen_string_literal: true

FileUtils.rm_f("coverage/.resultset.json")

SimpleCov.enable_coverage :branch
SimpleCov.primary_coverage :branch

SimpleCov.group "Presenters", "app/presenters"
SimpleCov.group "Services", "app/services"

SimpleCov.at_exit do
  SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter
  SimpleCov.result.format!
end
