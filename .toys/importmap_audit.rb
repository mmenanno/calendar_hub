# frozen_string_literal: true

desc("Audit importmap for vulnerable packages")

def run
  exec("bin/importmap audit")
end
