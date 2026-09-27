# frozen_string_literal: true

desc("Run project quality checks (rubocop, erb_lint, tests, brakeman, importmap audit)")
long_desc(
  "Runs every check in read-only mode (no autocorrection), stopping at the first failure.",
  "Use `toys rubocop` / `toys erblint` to apply safe autocorrections.",
)

include :exec
include :terminal

def run_stage(name, command)
  if exec(command).success?
    puts("** #{name} passed **", :green, :bold)
    puts
  else
    puts("** CI terminated: #{name} failed!", :red, :bold)
    exit(1)
  end
end

def run
  run_stage("Style Checker", "bin/rubocop")
  run_stage("Erb Lint", "bin/erb_lint --lint-all")
  run_stage("Tests", "bin/rails test")
  run_stage("Brakeman", "bin/brakeman --no-pager --quiet")
  run_stage("Importmap Audit", "bin/importmap audit")
end
