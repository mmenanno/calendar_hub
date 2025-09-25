# frozen_string_literal: true

desc("Run project quality checks (rubocop, erblint, tests, brakeman, importmap audit)")

include :exec
include :terminal

def run_stage(name, tool)
  if exec_tool(tool).success?
    puts("** #{name} passed **", :green, :bold)
    puts
  else
    puts("** CI terminated: #{name} failed!", :red, :bold)
    exit(1)
  end
end

def run
  run_stage("Style Checker", ["rubocop"])
  run_stage("Erb Lint", ["erblint"])
  run_stage("Tests", ["test"])
  run_stage("Brakeman", ["brakeman"])
  run_stage("Importmap Audit", ["importmap_audit"])
end
