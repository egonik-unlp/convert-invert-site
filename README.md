# convert-invert-site

A Spotify-playlist-to-Soulseek bridge: matches Spotify tracks against the Soulseek
network, scores candidates with a Levenshtein or rules+fine-tuned-LLM judge, and downloads the best
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

## Server deployment (auto-start on boot)

On the server this runs as a standing deployment at **`/srv/shared/docker/convert-invert/`**
(alongside `portainer`, `mysql`, `filebrowser`, …), not from this repo's working tree. That
compose file pulls the prebuilt images from ghcr
(`ghcr.io/egonik-unlp/convert-invert-{api,slsk,frontend}`), keeps `build:` contexts pointing
back at this repo for rebuilds, and every service is `restart: unless-stopped` so the whole
stack (db, redis, jaeger, slsk, api, frontend) comes up automatically after a reboot. Its
`.env` is a symlink to this repo's `.env`, so there's one source of secrets/tuning. Postgres
and Redis reuse the existing named volumes (`convert-invert-site_postgres_data` /
`_redis_data`) and downloads live in the `/srv/storage/downloads` bind mount, so data survives
redeploys.

```bash
cd /srv/shared/docker/convert-invert
docker compose ps                       # status
docker compose pull && docker compose up -d   # roll out newer ghcr images
docker compose build && docker compose push   # rebuild from source and publish to ghcr
```

`zig build up` / `serve` / `down` in this repo drive that same boot stack (via
`--project-directory /srv/shared/docker/convert-invert`), so they never spin up a second
conflicting copy.

## Soulseek engine (`slsk`)

Soulseek I/O (search, download, **and** share) is handled by a single `aioslsk`-based engine
service (`convert-host-downloads`). One login does everything, and — unlike the old Rust
`soulseek_rs` client — aioslsk uses the server-brokered "connect to peer" flow, so transfers
work from behind NAT/CGNAT (it connects **out** to reachable uploaders instead of only waiting
for inbound connections). The Rust backend keeps orchestration, judging, DB, Spotify, and the
API, and delegates all Soulseek calls to the engine over HTTP (`SLSK_URL`, default
`http://slsk:8080`).

The engine owns the Soulseek listener port (default `41000`, published by the `slsk` service).
For best download success, forward that port on your router — `zig build serve` attempts this
automatically via UPnP. Behind ISP carrier-grade NAT you can't fully open the port, but
aioslsk's connect-out still completes transfers whenever the uploader is reachable.

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

Start a Spotify sync from the CLI (backend must be up):

```bash
zig build sync -Dplaylist="https://open.spotify.com/playlist/<id>"   # or a bare id
#   -Dworkers=N  -Dchunk=N   (defaults 1 / 15)
```

Downloaded files are written to `DOWNLOADS_DIR` (default `/srv/storage/downloads`), a host
folder bind-mounted into the api and engine — set it in `.env` to change where music lands.
Each run files its completed tracks into a subfolder named after the originating Spotify
playlist (e.g. `/srv/storage/downloads/My Chill Mix/…`); the engine still shares the whole
`/downloads` tree, so foldering doesn't affect upload reputation.

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
# Download inactivity timeouts — free a stuck slot so it can't clog the pipeline (0 disables):
DOWNLOAD_QUEUED_TIMEOUT_SECS=45   # parked in the remote queue, not transferring
DOWNLOAD_STALL_TIMEOUT_SECS=30    # transferring but zero byte progress
DOWNLOAD_HARD_TIMEOUT_SECS=180    # absolute ceiling per attempt (keep generous for big files)
```

An inactive download (a peer parked in its remote queue, or connected but sending 0 bytes)
holds a scarce download-concurrency slot and keeps its chunk from finishing, so a few dead
peers can stall the whole run. The timeouts above abort such transfers, freeing the slot for a
fresh candidate/peer; the aborted peer is then cooled down (`PEER_COOLDOWN_SECS`) so retries
prefer someone else.

You can also **pause/resume downloads manually** from the dashboard header (the ⏸ toggle) or
the API (`POST /api/pipeline/pause`, `POST /api/pipeline/resume`, `GET /api/pipeline`).
Pausing keeps the workers running but parks the download stage — in-flight transfers abort and
wait, and no candidate/attempt budget is spent — so you can safely halt and resume a run.

Beyond the worker profile, the backend also avoids getting banned by (1) skipping the
Soulseek search entirely for tracks already downloaded, (2) pacing searches and retries with
jittered delays, and (3) cooling down a peer after one of its transfers fails so a single bad
peer is not hammered. In `WORKER_ACCOUNT_MODE=same` the API clamps `WORKER_COUNT` to `1`,
because logging one account in concurrently is a common ban trigger.

### Sharing

Sharing needs no extra setup or second account: the `slsk` engine shares the `/downloads`
directory on the same login it downloads with (Soulseek allows one login per account, and one
engine covers both). Files you download are shared back automatically for peer reputation.

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

## Judges

Every Soulseek candidate is scored by one judge, and only candidates above
`JUDGE_THRESHOLD` (0.75) are downloaded. Which judge runs is `JUDGE_BACKEND`:

| `JUDGE_BACKEND` | What it does |
| --- | --- |
| `levenshtein` (default) | Normalised string similarity between the filename and the Spotify metadata. No extra services. |
| `smol` | A deterministic rule engine in front of the fine-tuned SmolLM judge (`eduardogonik/smol-judge:c200-q8`) served by ollama. The rules settle ~83% of candidates without inference. |

A `RelativeMi` score is recorded alongside either judge for evaluation, in
`judge_submissions.relative_mi_score`.

### The smol judge

`smol` is a **two-stage** judge, not just a model call: a deterministic rule
engine answers what it can, and only the remainder reaches the model.

`smol-judge` itself is a 135M SmolLM2 fine-tuned on ~12,200 (Spotify metadata,
Soulseek filename) pairs. It answers with a **label** rather than a distance:

| Label | Meaning | Score |
| --- | --- | --- |
| `exact` | The requested recording. | 1.0 |
| `wrong_version` | Right song, wrong recording — remix, live, edit, instrumental. | 0.3 |
| `wrong_artist` | Title matches, different act performing. | 0.05 |
| `different` | An unrelated track. | 0.0 |

Only `exact` clears the threshold. That is the point of it: `Only Human` and
`Only Human (Skream Remix)` are nearly the same string, so Levenshtein scores
both high, and the remix gets downloaded. Q8_0 scores within noise of fp32
(92.5% vs 91.6% precision on 826 held-out rows) at ~200ms per candidate.

The score the pipeline acts on is derived from the label, not from the number
the model emits — a garbled number cannot flip a download decision. The model's
literal reply is still stored for auditing.

To enable it:

```bash
ollama pull eduardogonik/smol-judge:c200-q8
# the ollama service must listen on the docker bridge, not just loopback:
#   OLLAMA_HOST=0.0.0.0
echo 'JUDGE_BACKEND=smol' >> .env
docker compose up -d api
```

### The rule engine (stage one)

Before any inference, each candidate goes through the deterministic rule engine
in `judges/rules.rs`. Each rule returns a tier:

| Tier | Meaning |
| --- | --- |
| `Gold` | Final. Short-circuits — the model is never consulted. |
| `Weak` | Recorded but not trusted; the model still decides. |
| `Abstain` | No opinion; the model decides. |

Two things justify putting it in front of the model:

- **Cost.** It settles ~83% of real candidates with no inference at all, turning
  a 200-candidate query from ~40s of model time into a few seconds.
- **Accuracy.** On 826 held-out rows the hybrid beat the model alone (96.0% vs
  93.6% accuracy, 26 vs 32 wrong files accepted). The rules also catch a failure
  the model reliably gets wrong: a *different* track sitting in a folder named
  after the requested one — asking for "Unreasonable Behaviour" and being handed
  `…/Unreasonable Behaviour/The Sound Of The Big Babou.mp3`.

The rules were ported from `src/rules.ts` in the `smol-model-test` repo, where
they were developed against all 15,374 real (query, candidate) pairs and audited
by hand twice. `Weak` exists precisely because that audit found some rules
unreliable — `wrong_artist` was demoted after being wrong on both sampled rows.

| Tier | Rules |
| --- | --- |
| `Gold` | `R2_placeholder_leaf`, `R3_version_mismatch`, `R4_exact`, `R4b_exact_via_album`, `R5_no_title_overlap`, `R6_missing_title_token`, `R7_title_superset`, `R7b_title_plus_extra_word` |
| `Weak` | `W1_exact_short_title_folder_artist`, `W2_low_title_overlap`, `W3_wrong_artist_unverified` |
| `Abstain` | `A_defer_to_model` |

A verdict the rules settled is recorded with its model tagged
`eduardogonik/smol-judge:c200-q8+rules` and a `raw` of
`{"label":"exact","rule":"R4_exact"}`, so the judgement log tells the two stages
apart after the fact — and names the rule that fired.

Set `SMOL_JUDGE_RULES=0` (also `false` / `off`) to bypass the engine and measure
the model unaided. The default is on.

### Switching judges at runtime

The right judge depends on what the machine is doing. The same model answers in
~100ms on an idle host and 10–17s on one busy training something else, and at
200 candidates per search that is the difference between 20 seconds and half an
hour of judging per track. So the judge can be switched from the dashboard's
**Judgements** view without redeploying:

- Levenshtein ⇄ smol judge, and for the smol judge, which ollama it talks to.
- `POST /api/judge {"backend": "smol"|"levenshtein", "url": "http://…"}`,
  `POST /api/judge/reset` to drop the override.
- The override lives in Redis (`judge:backend`, `judge:url`) and takes effect on
  the **next run** — a run already in flight keeps the judge it started with.
  `/api/config` reports the effective judge and whether it is `env` or `override`.

The environment stays the source of truth; the override is a temporary lever
over it, and Reset returns to whatever the deployment configures.

If ollama is unreachable the run does not stop: `SMOL_JUDGE_FALLBACK` decides
whether the Levenshtein score stands in (default) or the candidate is rejected.
Either way the error is recorded on the judgement, so a degraded run is visible
rather than silent. See `.env.example` for the full `SMOL_JUDGE_*` set.

The model is trained in a separate repo (`smol-model-test`); `src/prompt.ts`
there and `judges/smol.rs` here render the same prompt, tagged `p1`. If one
changes, both must, and `PROMPT_VERSION` must be bumped — every stored judgement
records the version it was produced under.

### Judgement log

Every verdict is written to the `judgements` table (one row per candidate per
judge, upserted on re-judge) with the label, model, prompt version, latency,
the raw reply and any error. `GET /api/judgements` serves that log with a
summary over the same filters, and the dashboard's **Judgements** view renders
it: verdict mix, accept rate, latency, errors, and a filterable feed. The
per-track candidate modal groups candidates by verdict and shows what the judge
was asked and what it replied.

The `convert-invert/llm` Bun/LangChain service is a separate **experimental**
scorer, not part of `docker-compose.yml` and not called by the backend.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- [**System Overview & Data Flow**](docs/SYSTEM_OVERVIEW.md): High-level introduction and the lifecycle of a track.
- [**System Architecture**](docs/ARCHITECTURE.md): Deep dive into backend managers, the run cycle, and infrastructure roles.
- [**API, Database & Observability**](docs/API_AND_DATABASE.md): Reference for REST endpoints, schema, and tracing.
- [**Setup & Development**](docs/DEVELOPMENT.md): Guide for environment variables, local setup, and reliability overhaul context.
- [**Submodule Management**](docs/SUBMODULES.md): Instructions for handling the frontend and backend submodules.
