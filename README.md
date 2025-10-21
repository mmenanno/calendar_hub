# Calendar Hub

Calendar Hub consolidates subscribed calendars (for example, healthcare portals or generic ICS feeds), normalizes event data, and syncs everything into a single Apple Calendar via CalDAV. The app is built for self-hosting, ships with Docker support, and manages its own encryption keys—no master key required.

## Features

- Unify multiple ICS feeds into one Apple Calendar collection with per-source overrides.
- UI for managing sources, testing destinations, and monitoring upcoming events in real time.
- Event mapping and filter rules to normalize titles or drop noise before syncing.
- Background sync pipeline backed by Solid Queue, plus manual sync and pause controls.
- Credential encryption with automatic key management and rotation tools in Settings.

## Stack

- Ruby 3.4.5 (see `.ruby-version`)
- Rails 8 with Hotwire (Turbo + Stimulus) and Tailwind CSS
- Solid Cache / Solid Queue / Solid Cable on SQLite
- Thruster app server; Faraday and Nokogiri for HTTP + parsing
- Quality tooling: Toys task runner, RuboCop suite, ERB Lint, Brakeman, Minitest/WebMock, SimpleCov

## Development Quick Start

### Prerequisites

- Ruby 3.4.5 with Bundler (`gem install bundler`)
- SQLite 3 (ships with macOS and most Linux distributions)

### First run

```bash
bin/setup
```

`bin/setup` installs gems, prepares the database, clears temp files, and starts the development Procfile (`bin/dev`). Pass `--skip-server` to avoid automatically launching the dev server.

### Subsequent runs

```bash
bin/dev
```

`bin/dev` runs the Rails server, Tailwind watcher, and Solid Queue worker defined in `Procfile.dev`.

## Configuration Overview

### Apple CalDAV credentials (configure in the UI)

- Visit `Settings` to enter your Apple ID username and the app-specific password generated at appleid.apple.com.
- Credentials are stored encrypted using the app's credential key (see below) and are only used for CalDAV operations.

### Destination calendar

- In `Settings` (`/settings/edit`), set the default *Apple Calendar Identifier* to match the display name shown in Apple Calendar (for example, `Work`).
- Override the identifier per `CalendarSource` when you need a source to write to a different calendar.

### Calendar sources, mappings, and filters

- Each `CalendarSource` defines an ingestion URL and sync options such as frequency, windows, and default time zone.
- Event mappings let you rewrite titles or locations before they sync; filters can drop junk events entirely.
- Use the source detail page to run "Check Destination", force syncs, or archive/purge sources without deleting historic events.

### Credential encryption & persistent storage

- On first boot the app generates:
  - `storage/key_store.json` – JSON document containing the credential encryption key and `secret_key_base`.
- Rotate the credential key from Settings → *Rotate Credential Key*. Rotation re-encrypts all stored credentials in-place.
- Override the key location with `CALENDAR_HUB_CREDENTIAL_KEY_PATH` if you need to store it outside the repository path.
- Persist the entire `storage/` directory (and optionally `log/`) between deployments or container restarts to retain credentials, secret keys, and SQLite databases.

### URL defaults

Set `APP_HOST`, `APP_PROTOCOL`, and `APP_PORT` if you need generated URLs in emails or background jobs to point at a non-default hostname or port. Settings in the UI take precedence over environment variables when present.

## Background Sync Pipeline

1. `CalendarSource` configures the ingestion endpoint and target calendar.
2. `CalendarHub::Ingestion::GenericICSAdapter` fetches and normalizes ICS data.
3. Events persist to `CalendarEvent`, are broadcast via Turbo, and appear on the dashboard.
4. `CalendarHub::SyncService` invokes `AppleCalendar::Client` to upsert/delete events over CalDAV.
5. `SyncCalendarJob` (Solid Queue) orchestrates background work; you can trigger manual syncs or pauses from the UI.
6. Monitor background job throughput at `/admin/jobs` (Mission Control Jobs) and real-time connectivity at `/realtime`.

## Testing & Quality

```bash
toys checks
```

`toys checks` runs RuboCop, ERB Lint, Brakeman, and the full Minitest suite. Coverage reports land in `coverage/` (open with `toys cov`). Run these checks before committing changes.

## Deployment

### Docker (production)

```bash
docker build -t youruser/calendar_hub .
docker run -d \
  -p 80:80 \
  -v calendar_hub_storage:/rails/storage \
  -v calendar_hub_log:/rails/log \
  --env APP_HOST=calendar.example.com \
  --name calendar_hub \
  youruser/calendar_hub
```

Notes:

- No master key is required. `SECRET_KEY_BASE` is optional; when absent the container writes both keys into `storage/key_store.json` on first boot.
- `bin/docker-entrypoint` runs `bin/rails db:prepare` before starting the Thruster server listening on port 80.
- Map `storage/` to a persistent volume to keep encrypted credentials, secret keys, and SQLite databases.
- Override `CMD` or `PORT` if your platform expects a different process or port.

### GitHub Container Registry

- `.github/workflows/deploy.yml` builds and pushes `ghcr.io/<owner>/calendar_hub` when the `VERSION` file changes on `main` (release workflow).
- Image tags include `latest`, the git `sha`, and (if present) the value of `VERSION`.

## Environment Variables

- **Required:** none.
- **Recommended:**
  - `APP_HOST`, `APP_PROTOCOL`, `APP_PORT` – canonical host/protocol/port for generated URLs.
  - `PORT` – override default Thruster port (80 in Docker, 3000 locally if you run `rails server`).
- **Optional operational knobs:**
  - `SECRET_KEY_BASE` – supply your own secret; otherwise generated inside `storage/key_store.json`.
  - `CALENDAR_HUB_KEY_STORE_PATH` – custom path for the combined key store (defaults to `storage/key_store.json`).
  - `CALENDAR_HUB_CREDENTIAL_KEY_PATH` – legacy path override for the credential key; still honored for compatibility.
  - `APPLE_READONLY=true` – sync without issuing CalDAV deletes.
  - `SOLID_QUEUE_SEPARATE_WORKER=true` – run jobs in a separate worker process instead of the web process (by default jobs run inside Puma).
  - `WEB_CONCURRENCY`, `JOB_CONCURRENCY`, `RAILS_MAX_THREADS` – tune Puma and Solid Queue concurrency.
  - `RAILS_LOG_LEVEL` – set log verbosity (`info` by default).
  - `WARM_CACHE_ON_STARTUP=false` – opt out of cache warming (defaults to `true` in production, `false` elsewhere).

## Troubleshooting

- **Realtime updates in development:** ensure `bin/dev` is running the `web` and `jobs` processes; test broadcast connectivity at `/realtime` → "Send Test Broadcast".
- **CalDAV 400/403 errors:** use "Check Destination" on the source to confirm the discovered collection is writable.
- **No events syncing:** verify the source is Active with a valid ICS URL, the Pending count is > 0, and credentials are present; use "Force Sync" if the sync window blocks processing.
- **Credential key mismatch:** if the credential key file is lost, restore it from backup or rotate the key in Settings; without it previously stored credentials cannot be decrypted.
