# frozen_string_literal: true

# Need to use the default rake implimentation until there is official rails support
# https://github.com/dazuma/toys/issues/248
# expand :minitest, files: ["test/**/*_test.rb"], libs: ["test", "lib"]

alias_tool :style, :rubocop
alias_tool :tapioca, :rbi
alias_tool :tc, :typecheck

expand :rake
