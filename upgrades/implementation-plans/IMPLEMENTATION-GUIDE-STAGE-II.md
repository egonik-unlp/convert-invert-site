# Implementation Guide — Stage II Reliability Sweep

Companion to `PLAN-OVERHAUL-STAGE-II.md` (log forensics) and `COMPLETED-STEPS.md` (what shipped in Stage I).

## Context

Stage I fixed the `Failed to report task completion: channel closed` orchestration bug by moving spawned task lifecycle into a `JoinSet` owned by `Managers::run_cycle` (see `COMPLETED-STEPS.md`). A fresh `workerlogs.log` run confirmed that fix — `channel closed` is now at 0. The same run, however, exposes a new layer of system-level failures and behavioral weaknesses:

- 9 panics binding the Soulseek listener (`Os { code: 98, kind: AddrInUse }`) on ports 41000–41003.
- 5 `DB pool in download_track: timed out waiting for connection` errors.
- 4 `duplicate key value violates unique constraint "downloaded_file_track_uidx"` crashes.
- Only 17/184 playlist tracks downloaded (~9.2%), with 146 "consecutive empty results" exits and 129 peer disconnects.
- No graceful shutdown of the `soulseek_rs::Client` between run cycles.

**Goal of Stage II.** A single full-playlist run with zero listener panics, zero DB-pool timeouts, zero duplicate-key crashes, and a download rate bounded by P2P availability rather than by our own logic. We measure progress with the existing `analyze_run_log` binary, extended in Phase E.

## Findings, anchored to current code

1. **Listener port reuse.** `src/main.rs:62-76` and `src/internals/worker/worker_manager.rs:299-369` recreate a `Managers` (and inner `soulseek_rs::Client`) per 15-track chunk. The client is built at `src/internals/context/context_manager.rs:140-148` with a fixed `listen_port` (`config.listen_port`, derived 41000 + worker_index in `worker_manager.rs:279-297`) and `client.connect()` is called synchronously. Nothing calls `client.disconnect()` or `logout()` between chunks, and the next cycle re-binds the same port before the previous socket has fully released.

2. **DB pool exhaustion.** `src/internals/database/mod.rs:12-17` uses `r2d2::Pool::builder().build(manager)` with all defaults (pool size 10, 30s timeout). `src/internals/download/download_manager.rs:115-229` opens the DB connection at line 117 with a 5s timeout, then holds it through the entire network loop (`hard_deadline = 3 minutes`). `Managers::run_cycle` at `src/internals/context/context_manager.rs:175-179` holds an additional connection for the whole chunk. With `download_concurrency = 7` (`context_manager.rs:109`) the pool is one chunk-conn + 7 download-conns = 8/10 saturated for minutes at a time; anything else (judge, retry, search persistence) easily times out at 5s.

3. **Wrong `ON CONFLICT` target.** `src/internals/database/manager.rs:92-110` writes `ON CONFLICT (filename) DO UPDATE SET track = ...`. The migration `2026-05-23-010000_unique_download_per_track/up.sql` creates a *partial* unique index `downloaded_file_track_uidx ON downloaded_file(track) WHERE track IS NOT NULL` — that is the constraint the run is actually violating, and the upsert clause does not cover it.

4. **Aggressive search cutoff, no peer-aware retry.** `src/internals/search/search_manager.rs:154-223` exits after `count_cutoff = 3` consecutive empty polls (set in `context_manager.rs:273`), each `search_timeout_secs` (default 10s) — minimum 40s window. No distinction is made between "peers timed out" and "no candidates exist", and the log line at `search_manager.rs:208-212` reports `times = TIMES_WITH_NO_NEW_FILES` (the constant), not the runtime cutoff.

5. **No graceful Managers/Client shutdown.** `Managers::run_cycle` drops the `Arc<Client>` implicitly when the `Managers` value goes out of scope. This is the root cause of (1).

## Phases

The numbered ordering below is the suggested implementation order. Phases A and B touch independent files and can land in parallel after Phase E.

### Phase E — Observability for pool & listener health *(ship first)*

Small, no behavior change. Lets us measure A/B before/after the real fixes.

**Goal.** Surface listener bind failures, DB pool starvation, and duplicate-track inserts as headline analyzer metrics.

**Approach.**
- Extend `src/bin/analyze_run_log.rs` with three new counters: `listener_bind_panics`, `db_pool_timeouts`, `duplicate_track_insert_errors`. Use the same JSON-first/text-fallback parsing the existing analyzer uses.
- In `Managers::run_cycle` (later: `run_chunk`), log a one-shot snapshot of `db_pool.state().connections` and `idle_connections` at chunk start and chunk end. Add a helper in `src/internals/database/mod.rs` that takes a `&DbPool` and returns a structured pool snapshot — keep `Pool` opaque to the rest of the code.
- On every `DB pool ...` `anyhow::Context` site (currently `download_manager.rs:117`, `download_manager.rs:120`, `context_manager.rs:175-179`), log the pool snapshot before bubbling the error up.

**Files to touch.**
- `src/bin/analyze_run_log.rs`
- `src/internals/database/mod.rs`
- `src/internals/context/context_manager.rs`
- `src/internals/download/download_manager.rs`

**Acceptance.**
- `cargo run --bin analyze_run_log -- ../workerlogs.log` prints the three new metrics; against the current log file the numbers should reproduce the report (9 / 5 / 4).
- 2 new analyzer unit tests for the new patterns.

### Phase A — Stop the listener AddrInUse panics

**Goal.** One listener per worker lifetime, not per chunk.

**Approach.**
- Lift `Managers` out of the per-chunk loop in `src/internals/worker/worker_manager.rs:299-369`: build it once at the top of `run_worker` (using `worker_config` and the worker's assigned port), then call a new `Managers::run_chunk(&self, tracks)` for each chunk fetched from Redis. Mirror the same change in `src/main.rs:62-76`.
- Move `client.login()` (currently `src/internals/context/context_manager.rs:182`, inside `run_cycle`) into a new `Managers::start` step called once during construction. Add `Managers::shutdown(self)` at end-of-worker that calls `client.disconnect()` / `client.logout()` if the `soulseek_rs` v0.3.0 API exposes either. If it does not, drop the `Arc<Client>` in a controlled order and document the gap in this guide's *Out of scope* section.
- Convert the listener bind from a panic to an error: today `client.connect()` panics on `AddrInUse`. Inspect `soulseek_rs` v0.3.0 — if `connect` returns a `Result`, propagate it; if it panics, wrap the call in `std::panic::catch_unwind` as a stop-gap and convert into `anyhow::Error` so the worker exits cleanly instead of taking the process down. Capture the OS error code in the log line.
- Add `SO_REUSEADDR` only if the crate exposes a socket-options hook; otherwise leave it to the "out of scope" follow-up.

**Files to touch.**
- `src/internals/context/context_manager.rs` (Managers lifecycle: `new` → `start` (login) → `run_chunk` → `shutdown`; remove per-chunk login from `run_cycle`)
- `src/internals/worker/worker_manager.rs` (single `Managers` per `run_worker`, not per chunk)
- `src/main.rs` (mirror the change for the single-process path)

**Acceptance.**
- Across a full playlist run, each `worker_id` shows exactly one `connect` + one `login` log line.
- `analyze_run_log` reports `listener_bind_panics: 0`.
- If `client.disconnect()` exists, also exactly one `disconnect` line per worker.

### Phase B — Idempotent `downloaded_file` upserts

**Goal.** No more duplicate-key crashes on `downloaded_file_track_uidx`.

**Approach.**
- Change `upsert_downloaded_file` in `src/internals/database/manager.rs:92-110` so the conflict target matches the invariant the migration enforces: `on_conflict(dl::track)` with `do_update().set(dl::filename.eq(excluded(dl::filename)))`. Conceptually:

  ```text
  INSERT INTO downloaded_file (filename, track)
  VALUES ($1, $2)
  ON CONFLICT (track) WHERE track IS NOT NULL
  DO UPDATE SET filename = EXCLUDED.filename
  ```

- The existing `(filename)` unique index continues to protect against the rarer cross-track filename collision. If that constraint starts firing in real logs, treat it as a separate problem.
- The `downloaded_file_track_uidx` is *partial* (`WHERE track IS NOT NULL`). Verify Diesel's `on_conflict(dl::track)` can target the partial index in the version pinned in `Cargo.toml`; if Diesel rejects it, fall back to `diesel::sql_query` with the literal SQL above.
- No new migration is needed.

**Files to touch.**
- `src/internals/database/manager.rs` only.

**Acceptance.**
- A focused test in `manager.rs` (or a sibling integration test) inserts the same `(track, filename_a)` then `(track, filename_b)` and asserts the row count for that `track` stays at 1 with `filename = filename_b`.
- `analyze_run_log` reports `duplicate_track_insert_errors: 0` on a new run.

### Phase C — Stop holding DB/Redis connections during network work

**Goal.** No more `DB pool in download_track timed out waiting for connection`.

**Approach.**
- In `src/internals/download/download_manager.rs:115-229`, split the `spawn_blocking` body into three phases:
  1. **Pre-flight.** Acquire `conn` from `db_pool`, look up `track_id` via `DatabaseManager::get_judge_submission_id`, **release `conn`** before entering the status loop.
  2. **Network loop.** No long-held DB connection. Redis progress writes acquire a Redis connection per write (`redis_pool.get_timeout(...)`) and drop it immediately; writes are already paced at `log_every = 10s`, so this is cheap.
  3. **Post-flight.** On `DownloadStatus::Completed`, acquire `conn` again, call the persistence path (which now uses the Phase B upsert).
- In `Managers::run_cycle` (`src/internals/context/context_manager.rs:172-242`), stop holding `conn` across the entire chunk. Instead, the `process_track` helper (`context_manager.rs:245-…`) should acquire and release per-track. Persistence sites that need a connection take one short-lived borrow and drop it before any `await`.
- Add pool config knobs in `src/internals/database/mod.rs:12-17`:
  - `DB_POOL_MAX_SIZE` (default `download_concurrency * 2 + 4`).
  - `DB_POOL_TIMEOUT_SECS` (default 15).
  - Same shape for the Redis pool builder in `src/main.rs:41-43`.
- At startup, log a warning if `DB_POOL_MAX_SIZE < DOWNLOAD_CONCURRENCY + SEARCH_CONCURRENCY + 2`.

**Files to touch.**
- `src/internals/download/download_manager.rs`
- `src/internals/database/mod.rs`
- `src/main.rs` (Redis pool builder, startup warning)
- `src/internals/context/context_manager.rs` (per-track connection acquisition)

**Acceptance.**
- A run with `DOWNLOAD_CONCURRENCY=7` and default pool reports `db_pool_timeouts: 0`.
- Chunk-start and chunk-end pool snapshots from Phase E show `idle_connections` returning to roughly the pool max between chunks.

### Phase D — Search coverage and peer-aware exit

**Goal.** Move the captured download rate from ~9% toward what the underlying P2P actually supports, and surface real reasons for "no candidates".

**Approach.**
- Make the cutoff and timeout env-driven in `src/internals/utils/config/config_manager.rs` and `src/internals/context/context_manager.rs:273`. Proposed defaults: `count_cutoff = 5`, `search_timeout_secs = 12`.
- In `track_search_task` (`src/internals/search/search_manager.rs:154-223`), distinguish three exit reasons in the returned status and in the log line: `NoCandidatesFound`, `EmptyAfterPeerErrors`, `Cancelled`. The judge stage can then treat `EmptyAfterPeerErrors` as worth a second search pass with a relaxed query (e.g. drop artist suffix, normalize "Track Name - Remix" variants).
- Fix the misleading log at `search_manager.rs:208-212`: emit the runtime `count_cutoff` field, not the `TIMES_WITH_NO_NEW_FILES` constant.
- Add a one-shot search retry for tracks that exited with zero candidates: either reuse the existing `Track::Retry` path or add a `Track::SearchRetry` variant carrying the relaxed query. Wire it through `process_track`.

**Files to touch.**
- `src/internals/search/search_manager.rs`
- `src/internals/context/context_manager.rs`
- `src/internals/utils/config/config_manager.rs`

**Acceptance.**
- New run shows the exit log line reflecting the runtime cutoff.
- `analyze_run_log`: `empty_result_exits` strictly lower, `unique_downloaded_tracks` strictly higher than 17 on the same playlist. No exact percentage target — P2P quality is uncontrolled.

## Dependencies and ordering

1. **Phase E** ships first (analyzer + pool snapshots). No behavior change, but it gives us the headline numbers.
2. **Phase A** and **Phase B** ship in parallel — independent files.
3. **Phase C** depends on Phase B (post-flight insert uses the new upsert) and on Phase E (pool snapshots prove the starvation is gone).
4. **Phase D** ships last. Lowest blast radius; iterate on tuning once the system is stable.

## Verification

- Per-phase, in `convert-invert/`: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`.
- Phase B migration check: `make` from repo root (uses `Makefile`) brings up docker-compose and runs pending migrations; confirm `downloaded_file_track_uidx` exists.
- End-to-end: run a worker against the same playlist that produced `workerlogs.log`. Capture logs to a new file, then:
  ```
  cd convert-invert && cargo run --bin analyze_run_log -- ../<new-log>.log
  ```
  Expect after all phases:
  - `listener_bind_panics: 0`
  - `db_pool_timeouts: 0`
  - `duplicate_track_insert_errors: 0`
  - `unique_downloaded_tracks` strictly greater than 17

## Out of scope (do not lose track of)

- Replacing or vendoring `soulseek-rs` v0.3.0 to expose `SO_REUSEADDR` and a `Result`-returning bind. Only pursue if Phase A discovers there is no `client.disconnect()` and the panic stop-gap is still firing.
- Switching to a non-blocking Redis driver. Phase C makes the current blocking driver acceptable as long as connections are not held across `await` points.
- A per-track state machine (`Pending → Searching → CandidatesFound → Downloading → Downloaded / NoCandidates / FailedAfterRetries`). Valuable for observability and for surfacing "why didn't track X download?" in the UI, but a separate stage.
