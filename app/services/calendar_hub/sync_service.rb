# frozen_string_literal: true

module CalendarHub
  # Deprecation alias: all call sites should use CalendarHub::Sync::SyncService.
  # This file exists only for backward compatibility and will be removed in a
  # future release. See PERF-017.
  SyncService = ::CalendarHub::Sync::SyncService
end
