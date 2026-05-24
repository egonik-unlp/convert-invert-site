# Completed Overhaul Steps

## 2026-05-23

### Implemented: Phase 1 run-cycle task ownership

Files changed:

- `convert-invert/src/internals/context/context_manager.rs`
- `convert-invert/src/internals/database/manager.rs`

What changed:

- Replaced detached task-completion messages over `Track::TaskComplete` with a `tokio::task::JoinSet` owned by `Managers::run_cycle`.
- Removed `TaskCompletion` and the `Track::TaskComplete` enum variant.
- Added `ManagedTaskResult` so spawned search, judge, download, and retry-search tasks return completion state through their join handle instead of sending completion through the same work channel.
- Added a `process_track` helper to keep event persistence/scheduling separate from the select loop.
- Added `RunCycleShared` to keep the `process_track` helper below clippy's argument limit without extending the mutable database borrow across loop iterations.
- Changed failure handling so the first task failure is recorded, new queued work is dropped, already spawned tasks continue to be joined, and the run returns the original task error after draining. This is intended to prevent normal task failures from causing `Failed to report task completion: channel closed`.
- Removed the obsolete `Track::TaskComplete` no-op branch from database persistence.
- Added focused managed-task tests for success, returned errors, and panics.

Verification:

- `cargo fmt --check` passed in `convert-invert`.
- `cargo check` passed in `convert-invert`.
- `cargo test context_manager::tests` passed with 3 focused managed-task tests.
- `cargo test` passed in `convert-invert` with 14 library tests and 2 analyzer tests.
- `make check` passed from the repository root after fixing the clippy `too_many_arguments` failure.

Remaining follow-up:

- Add higher-level run-loop termination and failure-draining tests with fake managers or a narrower test seam.
- Add shutdown-aware cancellation to `run_cycle` instead of the current outer `tokio::select!` in `WorkerSupervisor::run_worker`.
- Validate with a real worker run that `Failed to report task completion` no longer appears in logs.

### Implemented: Phase 3 database guard for one successful download per track

Files changed:

- `convert-invert/migrations/2026-05-23-010000_unique_download_per_track/up.sql`
- `convert-invert/migrations/2026-05-23-010000_unique_download_per_track/down.sql`

What changed:

- Added a migration that deletes duplicate `downloaded_file` metadata rows for the same non-null `track`, keeping the lowest row ID.
- Added a partial unique index on `downloaded_file(track)` where `track IS NOT NULL`.
- Added a down migration that drops the index.

Verification:

- `cargo check` passed after adding the migration.
- `cargo test` passed after adding the migration.

Remaining follow-up:

- Run the migration against the dev database.
- Add a database test or migration smoke test proving duplicate track downloads are rejected.
- Decide whether duplicate successful candidate rows should be user-visible `AlreadyDownloaded` rejections or internal ignored events.

### Implemented: Phase 0 worker log analyzer

Files changed:

- `convert-invert/src/bin/analyze_run_log.rs`
- `convert-invert/README.md`

What changed:

- Added a Rust diagnostic binary that scans Docker worker logs and reports the reliability metrics from `IDEAS.md`.
- The analyzer parses JSON log payloads after the Docker prefix when possible, then falls back to text matching for non-JSON lines.
- It reports total lines, parsed JSON lines, warning/error counts, task-completion channel closures, unique searched tracks, downloaded file events, unique downloaded tracks, retry requests, empty-result exits, download timeout warnings, peer disconnects, connection failures, and duplicate successful downloads by `track_id`.
- Documented the command in `convert-invert/README.md`:

  ```bash
  cargo run --bin analyze_run_log -- ../worker-docker-logs.log
  ```

Verification:

- `cargo fmt --check` passed in `convert-invert`.
- `cargo check` passed in `convert-invert`.
- Added 2 analyzer parser unit tests.
- `cargo test --bin analyze_run_log` passed.
- `cargo test` passed in `convert-invert` with 14 library tests plus 2 analyzer tests.
- Running `cargo run --bin analyze_run_log -- ../worker-docker-logs.log` reproduced the key baseline numbers:
  - `task_completion_channel_closed: 49`
  - `unique_searched_tracks: 184`
  - `downloaded_file_events: 33`
  - `unique_downloaded_tracks: 25`
  - `retry_requests: 10`
  - `empty_result_exits: 192`
  - `peer_disconnects: 121`
  - `duplicate_downloaded_tracks: 6`

Remaining follow-up:

- Use the analyzer on a fresh worker run after the `JoinSet` refactor to confirm `task_completion_channel_closed` falls to zero.

## Current Resume Point

Recommended next step: add Phase 1 run-loop tests, then run a real playlist worker test and compare logs against `IDEAS.md` with `cargo run --bin analyze_run_log -- <new-log-file>`.
