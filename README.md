# convert-invert-site

A Spotify-playlist-to-Soulseek bridge: matches Spotify tracks against the Soulseek
network, scores candidates with a Levenshtein-based judge, and downloads the best
match. Rust + Actix backend, React + Vite frontend.

## Quick start

```bash
# 1. Copy the env templates and fill in real values
cp convert-invert/.env.example convert-invert/.env
cp convert-invert-frontend/.env.example convert-invert-frontend/.env.local

# 2. Also create a top-level .env for docker compose to pick up
cat > .env <<EOF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=convert_invert
DATABASE_URL=postgresql://postgres:\${POSTGRES_PASSWORD}@db:5432/convert_invert
API_KEY=$(openssl rand -hex 32)
ALLOWED_ORIGINS=http://localhost:5173
USER_NAME=your-soulseek-username
USER_PASSWORD=your-soulseek-password
CLIENT_ID=your-spotify-client-id
CLIENT_SECRET=your-spotify-client-secret
EOF

# 3. Boot
docker compose up --build
```

The API listens on `:3124`, the frontend on `:5173`, Jaeger UI on `:16686`.
Docker also publishes Soulseek listener ports `41000-41031` for worker P2P
traffic. If you change `WORKER_PORT_BASE` or run more than the default workers,
publish the same contiguous port range on the host and open it in the firewall.
The sharing sidecar uses the same `USER_NAME` / `USER_PASSWORD` by default and
publishes `SHARE_LISTEN_PORT` (default `41032`) while sharing the same
`/downloads` volume.

## Authentication

All `/api/*` endpoints require an `X-API-Key` header. The value must match the
backend's `API_KEY` env var. The frontend reads its key from `VITE_API_KEY` at
build time and attaches it to every request.

```bash
curl -H "X-API-Key: $API_KEY" http://localhost:3124/api/stats
```

Requests without the header return `401 Unauthorized`. Requests with a wrong key
also return `401` (comparison is constant-time).

## Rate limiting

`/api/*` is capped at 30 requests/minute per IP. `/api/workers/start` has a
stricter cap of 5 requests/minute. Exceeding either returns `429 Too Many Requests`.

## Required environment variables

| Variable | Where | Description |
|---|---|---|
| `DATABASE_URL` | backend | Postgres connection string |
| `API_KEY` | backend + frontend build | Shared secret for `X-API-Key` |
| `ALLOWED_ORIGINS` | backend | Comma-separated CORS allow-list |
| `USER_NAME` / `USER_PASSWORD` | backend | Soulseek credentials |
| `CLIENT_ID` / `CLIENT_SECRET` | backend | Spotify app credentials |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | compose | Postgres bootstrap |
| `VITE_API_KEY` | frontend | Same value as backend `API_KEY` |
| `VITE_API_BASE_URL` | frontend | Backend base URL (omit if same-origin) |

See `convert-invert/.env.example` and `convert-invert-frontend/.env.example`
for the complete list, including optional tuning knobs.

For unstable Soulseek peers or fresh accounts, start with a conservative worker
profile and increase gradually:

```env
WORKER_COUNT=1
WORKER_ACCOUNT_MODE=same
SEARCH_CONCURRENCY=1
DOWNLOAD_CONCURRENCY=1
SEARCH_TIMEOUT_SECS=20
SEARCH_EMPTY_RESULT_CUTOFF=8
MAX_DOWNLOAD_ATTEMPTS_PER_TRACK=4
MAX_CANDIDATES_PER_TRACK=8
MAX_SEARCH_PASSES_PER_TRACK=2
MAX_REQUESTS_PER_TRACK=8
```

Compose starts a dedicated sharing sidecar because the pinned Rust Soulseek
library advertises counts but does not reliably serve real uploaded files. The
supported default is `WORKER_ACCOUNT_MODE=same`: one downloading account, one
worker, and the sidecar logged in with the same `USER_NAME` while sharing
`SHARE_PATH` (default `/downloads`). Do not raise `WORKER_COUNT` above `1` in
this mode; use real separate Soulseek accounts before moving to a multi-account
setup.

## If you previously committed credentials

The earlier layout of this repo had `convert-invert/.env` and weak defaults in
`docker-compose.yml`. If any of those values ever reached a remote, rotate
them now and scrub the history (`git filter-repo --invert-paths --path convert-invert/.env`
or BFG). The `.gitignore` in this commit blocks new leaks but does not retroactively
clean existing ones.

## Development

```bash
# Backend
cd convert-invert
cargo run --bin trigger_server

# Frontend
cd convert-invert-frontend
npm install
npm run dev
```

## Repository structure

This workspace is intended to use Git submodules for the backend and frontend
component repositories. See [docs/SUBMODULES.md](docs/SUBMODULES.md) before
initializing, cloning, updating, or committing submodule pins.

## Project layout

```
convert-invert/                 Rust backend (Actix + Diesel + Soulseek)
  src/bin/trigger_server/       HTTP API entrypoint
  src/internals/                Domain modules (judge, download, context, ...)
  migrations/                   Diesel migrations
convert-invert-frontend/        React 19 + Vite + Tailwind + shadcn/ui
  components/                   View components
  components/ui/                shadcn primitives
docker-compose.yml              Postgres, Redis, Jaeger, API, frontend
```

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- [**System Overview & Data Flow**](docs/SYSTEM_OVERVIEW.md): High-level introduction and the lifecycle of a track.
- [**System Architecture**](docs/ARCHITECTURE.md): Deep dive into backend managers, the run cycle, and infrastructure roles.
- [**API, Database & Observability**](docs/API_AND_DATABASE.md): Reference for REST endpoints, schema, and tracing.
- [**Setup & Development**](docs/DEVELOPMENT.md): Guide for environment variables, local setup, and reliability overhaul context.
- [**Submodule Management**](docs/SUBMODULES.md): Instructions for handling the frontend and backend submodules.
