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

## Serve the dashboard on your LAN (`zig build serve`)

A small Zig launcher (`build.zig` + `tools/serve/`) serves the built UI on `0.0.0.0`
and reverse-proxies `/api` to the backend, so you can open the dashboard from another
machine on the network through a single origin (no CORS, no nginx, no Node to serve).
Requires Zig 0.16+.

```bash
# 1. Build the frontend bundle once (needs Node):
zig build ui
# 2. Make sure the backend is reachable on :3124, e.g.:
docker compose up -d api db redis jaeger
# 3. Serve on 0.0.0.0:8080 and proxy /api -> 127.0.0.1:3124
zig build serve
#    Options: -Dport=9000  -Dbackend-port=3124  -Dapi-key=<API_KEY>
```

Then browse from another PC at `http://<this-machine-LAN-IP>:8080` (find the IP with
`hostname -I`; open the port in your firewall). Passing `-Dapi-key=$API_KEY` makes the
launcher inject `X-API-Key` server-side, so the secret never needs to be baked into the
browser bundle. This is an alternative to the full compose frontend container — useful when
you only run the API and want a lightweight LAN server for the UI.

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
# Anti-ban pacing (set any to 0 to disable):
RETRY_BACKOFF_MS=1000       # jittered backoff before each retry
SEARCH_PACING_MS=500        # jittered delay before each search
PEER_COOLDOWN_SECS=120      # skip a peer after it fails a transfer
```

Beyond the worker profile, the backend also avoids getting banned by (1) skipping the
Soulseek search entirely for tracks already downloaded, (2) pacing searches and retries with
jittered delays, and (3) cooling down a peer after one of its transfers fails so a single bad
peer is not hammered. In `WORKER_ACCOUNT_MODE=same` the API clamps `WORKER_COUNT` to `1`,
because logging one account in concurrently is a common ban trigger.

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

## LLM judge (optional, not wired by default)

The `convert-invert/llm` Bun/LangChain service is an **experimental** secondary judge. It is
**not** part of `docker-compose.yml` and the backend does not call it — the active judge is
the Levenshtein scorer, with a `RelativeMi` score recorded alongside for evaluation. Run it
manually (`cd convert-invert/llm && bun install && bun index.ts`) only if you are iterating on
LLM-based scoring; wiring it into the judge path is a separate task.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- [**System Overview & Data Flow**](docs/SYSTEM_OVERVIEW.md): High-level introduction and the lifecycle of a track.
- [**System Architecture**](docs/ARCHITECTURE.md): Deep dive into backend managers, the run cycle, and infrastructure roles.
- [**API, Database & Observability**](docs/API_AND_DATABASE.md): Reference for REST endpoints, schema, and tracing.
- [**Setup & Development**](docs/DEVELOPMENT.md): Guide for environment variables, local setup, and reliability overhaul context.
- [**Submodule Management**](docs/SUBMODULES.md): Instructions for handling the frontend and backend submodules.
