# Calendar Hub

Calendar Hub is a private Rails 8 application that consolidates subscribed calendars (e.g. JaneApp providers or generic ICS feeds), normalizes the data, and syncs the sanitized events into a single Apple Calendar via CalDAV. It is tailored for a self-hosted workflow (Unraid + Docker) and keeps sensitive credentials in encrypted storage.

## Stack

- Ruby 3.4.5 (managed with `mise`)
- Rails 8 with Hotwire (Turbo + Stimulus) and Tailwind CSS
- Solid Cache / Solid Queue / Solid Cable on SQLite
- Faraday + custom ICS ingestion adapters
- Rubocop (Shopify config), ERB Lint, Brakeman, WebMock, Minitest

## Getting Started

```bash
bundle install --local
# One command prepares dev and test DBs, creating and loading schema if needed
bin/rails db:prepare

# Prepare Solid Cable DB (dev) to mirror production Cable
bin/rails db:cable:prepare

# Run the suite and start the app
bin/rails test
bin/dev                      # runs web, jobs (Solid Queue), and tailwind watcher
```

### Credentials

All external secrets live in encrypted Rails credentials. Add Apple CalDAV credentials:

```bash
bin/rails credentials:edit
```

```yaml
calendar_hub:
  apple_calendar:
    username: your-apple-id@example.com
    app_specific_password: xyz-app-pass
    # Optional: override the CalDAV host (defaults to caldav.icloud.com)
    # base_url: https://caldav.icloud.com
```

Per-source secrets such as HTTP basic auth usernames/passwords are stored encrypted on each `CalendarSource` record.

## Quality Gates

Toys-based quality checks mirror the Leviathan project:

```bash
bundle exec toys checks   # rubocop, erblint, tests, brakeman, importmap audit
bundle exec rubocop       # -f github formatting locally
bin/rails test            # system + unit tests
```

GitHub Actions (`.github/workflows/ci.yml`) run the same checks on pull requests.

## Synchronization Flow

1. `CalendarSource` records describe provider type, ingestion URL, and Apple calendar identifier.
2. Adapters under `CalendarHub::Ingestion` fetch and parse ICS feeds (JaneApp has custom field mapping and sanitization).
3. Events are persisted to `CalendarEvent` with encrypted metadata. Turbo streams broadcast changes to the UI.
4. `CalendarHub::SyncService` translates normalized events via provider-specific translators and delegates Apple writes to `AppleCalendar::Client`.
5. `SyncCalendarJob` (Solid Queue) orchestrates background refreshes. Manual sync and pause/resume toggles are exposed in the UI.

## Deployment

- Dockerfile is production ready: `docker build -t youruser/calendar-hub .`
- Push image to Docker Hub for Unraid to pull.
- Runtime settings are provided through environment variables (`RAILS_MASTER_KEY`, etc.).

## UI Overview

- Dashboard (`/`) lists upcoming events with live Turbo updates.
- Sidebar shows source health, quick sync/pause controls, and an inline form for adding feeds.
- Full management view at `/calendar_sources` for detailed configuration.
- Realtime diagnostics at `/realtime` — send a test broadcast to verify Cable delivery end‑to‑end.

## Safety & Privacy

- No client identifiers appear in clear-text on the dashboard; JaneApp translator masks names by default.
- Credentials are encrypted via Active Record Encryption.
- Sync operations short-circuit for paused/non-ingestable sources to avoid leaking data accidentally.

## Next Steps

- CalDAV write integration implemented: `AppleCalendar::Client` performs discovery and PUT/DELETE of `.ics` events. Configure Apple credentials above and set your destination calendar name (identifier) in Settings or per Source.
- Historical event audit logs: `CalendarEventAudit` records create/update/delete with before/after snapshots.
- Granular per-provider scheduling windows: optional start/end hours on each source restrict when Sync is enqueued in that source’s time zone.
- Per‑source progress + errors: each source card shows running status, totals, and recent errors with live updates.
- Force Sync: bypasses the scheduling window for immediate enqueuing; “Check Destination” verifies CalDAV discovery.

### Apple Calendar setup

1. Generate an Apple app‑specific password for your Apple ID and add it under Credentials above.
2. In the Settings page (`/settings/edit`), set the default “Apple Calendar Identifier” (the visible name in Calendar, e.g., “Work”). You can override this on each source.
3. Click “Sync” on a source or “Sync All”. The first sync performs CalDAV discovery and caches the calendar path.

If discovery fails to find your calendar, ensure the identifier matches the display name exactly in Apple Calendar.

### Troubleshooting

- Realtime updates don’t appear in dev:
  - Ensure `bin/dev` started both `web` and `jobs` processes, and run `bin/rails db:cable:prepare` once.
  - Visit `/realtime` and click “Send Test Broadcast”. If it updates, Cable is working.
- CalDAV 400 Bad Request on PUT:
  - Caused by an encoded absolute URL; the client now normalizes discovery results. Use “Check Destination” to revalidate.
- CalDAV 403 Forbidden on PUT:
  - Your destination calendar is likely read‑only. Use a writable calendar (a personal or iCloud account calendar, not a subscribed one).
- No events syncing:
  - Confirm the source is Active, has a valid ingestion URL, and Pending > 0 on the source card; click “Force Sync”.
