# frozen_string_literal: true

# Start each run from a clean slate so stale results from earlier runs are never
# merged in. Parallel test workers are forked processes: SimpleCov (>= 1.0)
# re-starts coverage in each fork and merges every worker's result in the
# parent, and test_helper names each worker via parallelize_setup.
FileUtils.rm_f("coverage/.resultset.json")

# Thresholds are enforced on CI (full-suite runs) only, so running a single
# test file locally doesn't fail on coverage. Set CI=1 to enforce locally.
line_minimum, branch_minimum = ENV["CI"].present? ? [85, 80] : [nil, nil]
SimpleCov.coverage(:line, **{ minimum: line_minimum }.compact)
SimpleCov.coverage(:branch, primary: true, **{ minimum: branch_minimum }.compact)

SimpleCov.group("Presenters", "app/presenters")
SimpleCov.group("Services", "app/services")
