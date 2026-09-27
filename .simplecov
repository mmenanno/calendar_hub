# frozen_string_literal: true

# Start each run from a clean slate so stale results from earlier runs are never
# merged in. Parallel test workers are forked processes: SimpleCov (>= 1.0)
# re-starts coverage in each fork and merges every worker's result in the
# parent, and test_helper names each worker via parallelize_setup.
FileUtils.rm_f("coverage/.resultset.json")

SimpleCov.coverage(:line, minimum: 85)
SimpleCov.coverage(:branch, primary: true, minimum: 80)

SimpleCov.group("Presenters", "app/presenters")
SimpleCov.group("Services", "app/services")
