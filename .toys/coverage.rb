# frozen_string_literal: true

desc("Open the simplecov coverage report")

def run
  exec("open coverage/index.html")
end
