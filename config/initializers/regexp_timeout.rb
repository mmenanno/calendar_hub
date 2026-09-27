# frozen_string_literal: true

# Backstop for any regex match that doesn't go through CalendarHub::SafeRegexp
# (which applies its own, shorter timeout to user-supplied patterns).
Regexp.timeout = 2.0
