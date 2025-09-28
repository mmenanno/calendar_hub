# frozen_string_literal: true

FileUtils.rm_f("coverage/.resultset.json")

SimpleCov.start("rails") do
  enable_coverage :branch
  primary_coverage :branch

  add_group "Presenters", "app/presenters"
  add_group "Services", "app/services"

  at_exit do
    SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter
    SimpleCov.result.format!
  end
end
