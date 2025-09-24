# frozen_string_literal: true

desc("Serve project documentation with Jekyll")

def run
  exec("bundle exec jekyll serve --source docs --destination docs/_site --trace")
end
