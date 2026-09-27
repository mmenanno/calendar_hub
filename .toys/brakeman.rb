# frozen_string_literal: true

desc("Run the Brakeman security scanner")

def run
  exec("bin/brakeman --no-pager")
end
