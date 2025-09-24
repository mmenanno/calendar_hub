# frozen_string_literal: true

desc("Run ERB lint on all templates and apply safe corrections")

def run
  exec("bin/erb_lint --lint-all -a")
end
