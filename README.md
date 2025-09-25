# Calendar Hub

Calendar Hub consolidates subscribed calendars (e.g., healthcare providers or generic ICS feeds), normalizes events, and syncs them into a single Apple Calendar via CalDAV. Built for self‑hosting with Docker; secrets are encrypted.

## Stack

- **Ruby**: 3.4.5 (see `.ruby-version`)
- **Rails**: 8 (Hotwire: Turbo + Stimulus) + Tailwind CSS
- **Solid**: Solid Cache / Solid Queue / Solid Cable on SQLite
- **HTTP/Parsing**: Faraday, Nokogiri
- **Quality**: Rubocop, ERB Lint, Brakeman, Minitest/WebMock

## Quick start (development)

```bash
# First run
bin/setup

# Subsequent runs
bin/dev
```

## Configuration

### Apple CalDAV credentials (configure in UI)

- In the app, open `Settings` and enter your Apple ID username and an app‑specific password. These are stored securely and used for CalDAV.
- Per‑source HTTP Basic credentials are stored encrypted on each `CalendarSource`.

### Destination calendar

- In `Settings` (`/settings/edit`), set the default “Apple Calendar Identifier” (exact display name in Apple Calendar, e.g., "Work").
- You can override the identifier per `CalendarSource`.

## How it works

1. `CalendarSource` defines the ingestion URL and destination calendar identifier.
2. `CalendarHub::Ingestion::GenericICSAdapter` fetches/parses ICS and normalizes fields.
3. Events are persisted to `CalendarEvent` and broadcast to the UI via Turbo.
4. `CalendarHub::SyncService` translates events and calls `AppleCalendar::Client` to upsert/delete over CalDAV.
5. `SyncCalendarJob` (Solid Queue) orchestrates background sync; manual sync/pause available in the UI.

Key screens/routes:

- `/` upcoming events; `/calendar_sources` manage sources; `/settings` app settings; `/realtime` Cable diagnostics.

## Testing & quality

```bash
toys checks
```

## Deployment

### Docker (production)

```bash
docker build -t youruser/calendar_hub .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=... \
  --name calendar_hub youruser/calendar_hub
```

Notes:

- Container listens on port 80 by default (Thruster). Override `CMD` if needed.
- Use a persistent volume for `storage/` if you store uploads.

### GitHub Container Registry

- Workflow `.github/workflows/deploy.yml` builds and pushes `ghcr.io/<owner>/calendar_hub` on pushes to `main`.
- Tags include `latest`, `sha`, and optional contents of `VERSION`.

## Environment variables

- **Required**: `RAILS_MASTER_KEY`
- **Optional**:
  - `APPLE_READONLY=true` to skip deletes against CalDAV
  - `SOLID_QUEUE_IN_PUMA` (true to run jobs in web process)
  - `WEB_CONCURRENCY`, `JOB_CONCURRENCY` for tuning

## Troubleshooting

- **Realtime updates in dev**: ensure `bin/dev` is running `web` and `jobs`; test at `/realtime` → “Send Test Broadcast”.
- **CalDAV 400 on PUT**: re‑run “Check Destination” on a source; ensure discovery selected the correct collection.
- **CalDAV 403 on PUT**: destination calendar is read‑only; choose a writable personal/iCloud calendar.
- **No events syncing**: source must be Active with a valid ICS URL; check Pending count; use “Force Sync”.
