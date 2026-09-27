# Calendar Hub

Calendar Hub consolidates subscribed calendars (for example, healthcare portals or generic ICS feeds), normalizes event data, and syncs everything into a single Apple Calendar via CalDAV. The app is built for self-hosting, ships with Docker support, and manages its own encryption keys—no master key required.

## Features

- Unify multiple ICS feeds into one Apple Calendar collection with per-source overrides.
- UI for managing sources, testing destinations, and monitoring upcoming events in real time.
- Event mapping and filter rules to normalize titles or drop noise before syncing.
- Import and export of mappings and filter rules as versioned JSON, with a preview step (duplicates, unknown sources, invalid rows) and append or replace modes.
- Background sync pipeline backed by Solid Queue, plus manual sync and pause controls.
- Credential encryption with automatic key management and rotation tools in Settings.

## Stack

- Ruby (see `.ruby-version` for the exact version)
- Rails 8 with Hotwire (Turbo + Stimulus) and Tailwind CSS
- Solid Cache / Solid Queue / Solid Cable on SQLite
- Thruster app server; Faraday and Nokogiri for HTTP + parsing
- Quality tooling: Toys task runner, RuboCop suite, ERB Lint, Brakeman, Minitest/WebMock, SimpleCov

## Development Quick Start

### Prerequisites

- Ruby matching `.ruby-version`, with Bundler (`gem install bundler`)
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

`bin/dev` runs the Rails server and Tailwind watcher defined in `Procfile.dev`. Background jobs run inside the Puma process via the Solid Queue plugin (as in production); set `SOLID_QUEUE_SEPARATE_WORKER=true` and run `bin/jobs` in another terminal if you prefer a separate worker.

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
- Rotate the credential key from Settings → *Rotate Credential Key*. Rotation re-encrypts all stored credentials in-place. Other processes (e.g. a separate Solid Queue worker) notice the new key file on their next encrypt/decrypt; no restart is needed.
- The key store is written atomically (owner-only `0600` temp file renamed into place), and the previous version is kept as `key_store.json.bak` next to it, so the key from before the last rotation is never lost.
- If `key_store.json` exists but is empty or not valid JSON, the app refuses to start instead of generating new keys (which would make every stored credential undecryptable). Restore it from a backup, or delete it to start over with new keys and re-enter your credentials.
- Credentials that can't be decrypted with the current key are never silently dropped: Settings shows a warning listing them, syncs fail with a message saying so, and saving other settings leaves them untouched. They're replaced only when you re-enter them.
- Override the key store location with `CALENDAR_HUB_KEY_STORE_PATH` if you need to store it outside the repository path.
- Persist the entire `storage/` directory (and optionally `log/`) between deployments or container restarts to retain credentials, secret keys, and SQLite databases.

### URL defaults

Set `APP_HOST`, `APP_PROTOCOL`, and `APP_PORT` if you need generated URLs in emails or background jobs to point at a non-default hostname or port. Settings in the UI take precedence over environment variables when present.

## Background Sync Pipeline

1. `CalendarSource` configures the ingestion endpoint and target calendar.
2. `CalendarHub::Ingestion::GenericICSAdapter` fetches and normalizes ICS data.
3. Events persist to `CalendarEvent`, are broadcast via Turbo, and appear on the dashboard.
4. `CalendarHub::Sync::SyncService` invokes `AppleCalendar::Client` to upsert/delete events over CalDAV.
5. `SyncCalendarJob` (Solid Queue) orchestrates background work; you can trigger manual syncs or pauses from the UI.
6. Monitor background jobs and sync activity on the built-in jobs dashboard at `/admin/jobs`, and real-time connectivity at `/realtime`.

## Testing & Quality

```bash
toys checks
```

`toys checks` runs, in order and without autocorrecting anything: RuboCop, ERB Lint, the full Minitest suite (`bin/rails test`), Brakeman, and `importmap audit`, stopping at the first failure. Use `toys rubocop` (`-A` for unsafe fixes) and `toys erblint` to apply autocorrections.

Coverage reports land in `coverage/` (open with `toys cov`). CI enforces minimum coverage of 85% lines / 80% branches; set `CI=1` to enforce it locally. Run these checks before committing changes.

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
- `bin/docker-entrypoint` runs `bin/rails db:prepare` before starting the Thruster server listening on port 80 (`HTTP_PORT`).
- **Put a TLS-terminating reverse proxy in front of the container** (Caddy, Traefik, nginx, Cloudflare Tunnel, ...). Production forces SSL (`force_ssl`, HSTS, secure cookies) and assumes the proxy terminates TLS (`assume_ssl`), so browsing the app over plain HTTP breaks (secure session and CSRF cookies are never sent).
- Map `storage/` to a persistent volume to keep encrypted credentials, secret keys, and SQLite databases.
- The container runs as uid/gid `1000`. For bind mounts, make the host directory writable by that user (`sudo chown -R 1000:1000 /path/to/storage /path/to/log`). Images built before this change used a system uid, so existing volumes need the same one-time `chown` after upgrading.
- The image defines a `HEALTHCHECK` that requests `/up`; orchestrators can use it for readiness.
- Override `CMD` or `HTTP_PORT` if your platform expects a different process or port.

### GitHub Container Registry

- `.github/workflows/deploy.yml` builds a multi-arch (`linux/amd64`, `linux/arm64`) image and pushes `ghcr.io/<owner>/calendar_hub` on every push to `main`.
- Every build is tagged `latest` and `sha-<commit>`. When `VERSION` changes, the build is also tagged with that version and a GitHub Release is created.

## Backups & restore

Everything the app needs lives in `storage/`: the SQLite databases (in production `production.sqlite3`, `production_cache.sqlite3`, `production_queue.sqlite3`, `production_cable.sqlite3`) and `key_store.json` (credential encryption key and `secret_key_base`). **Back up `key_store.json` together with the databases.** Without it, stored CalDAV credentials cannot be decrypted.

### Taking backups

- `BackupJob` takes a snapshot automatically once it is scheduled in `config/recurring.yml` (daily by default).
- Run one on demand with `bin/rails calendar_hub:backup` (in Docker: `docker exec calendar_hub bin/rails calendar_hub:backup`).

Each run writes `calendar_hub-YYYYMMDD-HHMMSS/` (UTC) under `CALENDAR_HUB_BACKUP_DIR` (default `storage/backups`). Every database is copied with SQLite's `VACUUM INTO`, which produces a consistent copy while the app is running, and `key_store.json` (plus `key_store.json.bak`, the key store from before the last key rotation) is copied alongside it. Snapshot files are readable only by the app user (`0600`). Only the newest `CALENDAR_HUB_BACKUP_KEEP` snapshots (default 7) are kept.

The default location sits inside the `storage/` volume, so it protects against bad migrations or accidental deletes but not against losing the volume. Point `CALENDAR_HUB_BACKUP_DIR` at a separate mount, or sync the directory off-host, for real disaster recovery.

### Restoring

1. Stop the app, e.g. `docker stop calendar_hub`. Nothing may write to the databases during a restore.
2. Pick a snapshot, e.g. `storage/backups/calendar_hub-20260101-030000/`.
3. In the `storage/` directory, delete the current database files **and their `-wal`/`-shm` sidecar files** (`production*.sqlite3*`), so stale WAL data isn't replayed on top of the restored copy.
4. Copy the snapshot's `*.sqlite3` files and `key_store.json` into `storage/`. The snapshot files already use the same names.
5. Make sure the files are owned by the container user: `chown 1000:1000 storage/*.sqlite3 storage/key_store.json && chmod 600 storage/key_store.json`.
6. Start the app again. `bin/docker-entrypoint` runs `db:prepare`, which applies any migrations newer than the backup.

## Environment Variables

- **Required:** none.
- **Recommended:**
  - `APP_HOST`, `APP_PROTOCOL`, `APP_PORT` – canonical host/protocol/port for generated URLs.
  - `HTTP_PORT` – port Thruster listens on in Docker (default 80). `PORT` sets the Puma port (3000 locally; Thruster proxies to it in Docker).
  - `HONEYBADGER_API_KEY` – enables Honeybadger error reporting and Insights. Without it nothing is sent.
- **Optional operational knobs:**
  - `SECRET_KEY_BASE` – supply your own secret; otherwise generated inside `storage/key_store.json`.
  - `CALENDAR_HUB_KEY_STORE_PATH` – custom path for the combined key store (defaults to `storage/key_store.json`).
  - `CALENDAR_HUB_CREDENTIAL_KEY_PATH` – no longer read (the credential key lives in the key store); use `CALENDAR_HUB_KEY_STORE_PATH`.
  - `APPLE_READONLY=true` – sync without issuing CalDAV deletes.
  - `SOLID_QUEUE_SEPARATE_WORKER=true` – run jobs in a separate worker process instead of the web process (by default jobs run inside Puma).
  - `WEB_CONCURRENCY`, `JOB_CONCURRENCY`, `RAILS_MAX_THREADS` – tune Puma and Solid Queue concurrency.
  - `RAILS_LOG_LEVEL` – set log verbosity (`info` by default).
  - `HONEYBADGER_SQL_EVENT_SAMPLE_RATE` – percentage (0-100) of SQL Insights events sent to Honeybadger (default `5`).
  - `CALENDAR_HUB_BLOCK_PRIVATE_FEEDS=true` – refuse to fetch feeds (including "Test Feed" and every redirect hop) whose host resolves to a loopback, private (RFC 1918 / IPv6 ULA), link-local (incl. cloud metadata `169.254.169.254`), CGNAT, multicast or unspecified address; connections are pinned to the checked address. Off by default so feeds on your LAN keep working; turn it on if untrusted users can add sources.
  - `CALENDAR_HUB_MAX_FEED_BYTES` – maximum feed download size in bytes (default `10485760`, 10 MB). Feed fetches must also finish within 45 seconds in total, and only `http://`, `https://` and `webcal://` URLs are accepted.
  - `CALENDAR_HUB_BACKUP_DIR`, `CALENDAR_HUB_BACKUP_KEEP` – backup location (default `storage/backups`) and number of snapshots to keep (default `7`). See [Backups & restore](#backups--restore).

## Troubleshooting

- **Realtime updates in development:** ensure `bin/dev` is running (jobs run inside the `web` process); test broadcast connectivity at `/realtime` → "Send Test Broadcast".
- **CalDAV 400/403 errors:** use "Check Destination" on the source to confirm the discovered collection is writable.
- **No events syncing:** verify the source is Active with a valid ICS URL, the Pending count is > 0, and credentials are present; use "Force Sync" if the sync window blocks processing.
- **Credential key mismatch:** if `key_store.json` was lost or replaced, Settings shows a warning listing the credentials that can't be decrypted, and syncs fail with "Stored credentials can't be decrypted". Stop the app, restore `key_store.json` from a backup (see [Backups & restore](#backups--restore); `key_store.json.bak` holds the key from before the last rotation) and start it again, or re-enter the listed credentials in Settings and on each affected source. Rotating the key doesn't help: it can only re-encrypt credentials the current key can read.
- **App won't start: "Key store … is not valid JSON" / "is empty":** the key store file is damaged. Restore it from a backup, or delete it to generate new keys and then re-enter all stored credentials.
