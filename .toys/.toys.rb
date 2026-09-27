# frozen_string_literal: true

# Need to use the default rake implimentation until there is official rails support
# https://github.com/dazuma/toys/issues/248
# expand :minitest, files: ["test/**/*_test.rb"], libs: ["test", "lib"]

tool "style", delegate_to: "rubocop"
tool "cov", delegate_to: "coverage"

expand :rake
