# Setup & Development Guide

This guide covers the necessary steps to set up, configure, and develop for `convert-invert-site`.

## Prerequisites
- **Rust**: Latest stable version.
- **Node.js / Bun**: For the LLM service.
- **Docker & Docker Compose**: For the full infrastructure (Postgres, Redis, Jaeger).
- **Spotify API Credentials**: `CLIENT_ID` and `CLIENT_SECRET` from the [Spotify Developer Dashboard](https://developer.spotify.com/).
- **Soulseek Credentials**: A valid username and password.

## Environment Variables
The system uses several `.env` files. Templates are provided:
- `.env.example` (Root): Shared infrastructure config.
- `convert-invert/.env.example`: Backend specific tuning (concurrency, timeouts).
- `convert-invert-frontend/.env.example`: Frontend API base URL.

### Key Tuning Knobs
- `SEARCH_CONCURRENCY`: Number of concurrent searches per worker.
- `DOWNLOAD_CONCURRENCY`: Number of concurrent downloads per worker.
- `DB_POOL_MAX_SIZE`: Should be at least `SEARCH_CONCURRENCY + DOWNLOAD_CONCURRENCY + 2`.

---

## Development Workflows

### 1. Docker-Based (Recommended for Infrastructure)
The easiest way to get the database, Redis, and Jaeger running is via Docker:
```bash
docker compose up -d db redis jaeger
```

### 2. Native Development (Fast Iteration)
For active development on the backend or frontend:

**Backend (Rust)**:
```bash
cd convert-invert
# Run migrations
diesel migration run
# Start the server
cargo run --bin trigger_server
```

**Frontend (React)**:
```bash
cd convert-invert-frontend
npm install
npm run dev
```

**LLM Service (Node/Bun)**:
```bash
cd convert-invert/llm
bun install
bun index.ts
```

---

## Stage II Reliability Overhaul

The project recently underwent a major reliability overhaul (Stage II) to address systemic issues identified in early logs. Key improvements include:

- **Listener Stability**: The Soulseek listener is now created once per worker lifetime rather than per chunk, preventing `AddrInUse` panics.
- **DB Pool Management**: Managers no longer hold database connections during long network operations (downloads), preventing pool exhaustion.
- **Idempotent Upserts**: Fixed duplicate-key crashes when recording successful downloads.
- **Task Ownership**: Implemented `tokio::task::JoinSet` in the run cycle to guarantee all spawned work is accounted for before a worker exits.

For more details, see the original plans: `PLAN-OVERHAUL-STAGE-II.md` and `IMPLEMENTATION-GUIDE-STAGE-II.md`.

## Common Commands
- **Check code quality**: `make check` (runs fmt, clippy, and tests).
- **Run migrations**: `cd convert-invert && diesel migration run`.
- **Analyze logs**: `cd convert-invert && cargo run --bin analyze_run_log -- <log_file>`.
- **Generate documentation**: `cd convert-invert && cargo doc --no-deps --open` (builds and opens the Rust library documentation).
