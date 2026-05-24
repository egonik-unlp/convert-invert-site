# Convert Invert Overhaul Implementation Plan

## Source Findings

This plan incorporates the recommendations from `IDEAS.md`, which analyzed `worker-docker-logs.log` and identified the following concrete issues:

- Workers fetched a Spotify playlist with 184 tracks, searched all 184 unique track IDs, but downloaded only 25 unique tracks.
- The most suspicious internal failure was repeated `Failed to report task completion: channel closed`, mostly from search tasks.
- Peer/download instability is expected in Soulseek-like P2P workflows, but the app needs to treat timeouts, refusals, and disconnects as first-class outcomes.
- Several tracks were downloaded more than once, suggesting candidate/download deduplication is not strict enough once a track succeeds.
- Search cutoff behavior is active but opaque: many searches exit after consecutive empty result rounds without leaving a clear final per-track outcome.
- The current UI/API infer track status from `search_items`, `judge_submissions`, `downloaded_file`, `rejected_track`, and Redis progress rather than from an explicit lifecycle model.

The current codebase already has useful foundations:

- `convert-invert/src/internals/context/context_manager.rs` owns the run-cycle message loop and task scheduling.
- `spawn_managed` reports task completion through `Track::TaskComplete`.
- `SearchManager`, `JudgeManager`, and `DownloadManager` divide the pipeline into clear stages.
- `WorkerSupervisor` distributes playlist chunks through Redis.
- Diesel migrations already enforce several uniqueness constraints.
- The trigger API and React frontend already expose dashboard, worker, playlist, status, candidate, log, and stats surfaces.

The overhaul should preserve those boundaries while making task ownership, per-track state, retry decisions, and observability explicit.

## Goals

1. Eliminate `channel closed` task-completion reports during normal runs.
2. Guarantee each spawned task is accounted for before a run cycle exits.
3. Persist a single authoritative per-track lifecycle state.
4. Make every track end in an explainable terminal state: downloaded, rejected, no candidates, failed after retries, banned, or cancelled.
5. Prevent duplicate successful downloads for a single source track.
6. Separate expected peer failures from internal orchestration failures in logs and API responses.
7. Improve operator visibility in the existing dashboard without requiring log forensics.

## Non-Goals

- Do not rewrite the app around a new queue system unless the scoped run-cycle changes fail to stabilize the workers.
- Do not replace `soulseek_rs`.
- Do not redesign the whole frontend. Extend the current dashboard and table flow.
- Do not tune search quality with an LLM judge until lifecycle accounting is reliable.

## Phase 0: Baseline and Reproduction

### Tasks

1. Save a reproducible baseline run profile.
   - Input: the playlist ID used in the failing log or another known 100+ track playlist.
   - Worker config: record `worker_count`, `chunk_size`, `SEARCH_CONCURRENCY`, `DOWNLOAD_CONCURRENCY`, and `SEARCH_TIMEOUT_SECS`.
   - Output: preserve Docker logs and `/api/stats`, `/api/workers/status`, `/api/playlists/all`, and `/api/logs` snapshots.

2. Add a short runbook section to `HANDOFF.md` or `convert-invert/README.md`.
   - Exact command to start the stack.
   - Exact API request used to start workers.
   - Exact commands used to collect logs and API snapshots.

3. Create an automated log regression check.
   - Add a small script or test fixture that scans run logs for:
     - `Failed to report task completion`
     - `channel closed`
     - duplicate `Downloaded file` events per `track_id`
     - tracks with `Query` but no terminal state
   - Keep this as a diagnostic script if full integration testing is too expensive.

### Acceptance Criteria

- A developer can reproduce the baseline and compare future runs against it.
- The current failure signature is measurable without manually reading thousands of log lines.

## Phase 1: Fix Run-Cycle Task Ownership

### Problem

`Managers::run_cycle` in `context_manager.rs` tracks `active_tasks` and uses `Track::TaskComplete` messages sent through the same channel as normal pipeline events. The log analysis shows that spawned tasks can attempt to report completion after the receiver has closed. That means the parent loop is exiting before all task handles are fully drained, or an error path closes the receiver while detached tasks are still alive.

### Design

Replace detached task accounting with explicit task ownership:

- Keep a `tokio::task::JoinSet` inside `run_cycle`.
- Spawn search, judge, retry-search, and download tasks into the `JoinSet`.
- Let tasks send normal pipeline events through the channel, but return their completion/error through the join result.
- Continue draining both:
  - channel events from managers
  - task completions from the `JoinSet`
- Exit only when:
  - the initial queue is empty,
  - the channel has no pending messages,
  - and the `JoinSet` has no remaining tasks.

### Concrete Changes

1. Update `convert-invert/src/internals/context/context_manager.rs`.
   - Remove or retire `Track::TaskComplete` and `TaskCompletion` from normal control flow.
   - Replace `spawn_managed` with a helper that inserts into a `JoinSet`.
   - Track task labels in the returned task result, for example:

   ```rust
   struct ManagedTaskResult {
       label: &'static str,
       result: anyhow::Result<()>,
   }
   ```

2. Change the run loop to use `tokio::select!`.
   - One branch receives `Track` messages.
   - One branch joins the next finished task.
   - The loop termination condition should be centralized in a small helper to avoid off-by-one exits.

3. Preserve panic handling.
   - Keep `AssertUnwindSafe(...).catch_unwind()` or equivalent wrapper around spawned task bodies.
   - Convert panics into failed task results that include the task label.

4. Add shutdown semantics.
   - `run_worker` currently races `managers.run_cycle(tracks)` against `shutdown.changed()`.
   - Decide whether mid-cycle shutdown cancels work immediately or asks `run_cycle` to drain.
   - Prefer adding a cancellation receiver to `run_cycle` so it can stop scheduling new work, drain in-flight tasks for a bounded interval, then abort remaining task handles deliberately.

### Tests

- Unit-test the run-loop termination helper.
- Add a test with fake managers or a test-only event handler where:
  - a task sends several events and completes late,
  - a task errors,
  - a task panics,
  - no initial tracks are provided.
- Verify the receiver is not dropped before all task completions are observed.

### Acceptance Criteria

- Normal runs no longer log `Failed to report task completion`.
- A failed task produces one structured run-cycle error with the task label.
- The run cycle cannot finish while spawned work is still pending.

## Phase 2: Add Authoritative Track Lifecycle State

### Problem

The app currently infers status from separate persistence side effects:

- `search_items` means the track entered the system.
- `judge_submissions` means candidates were found and/or judged.
- `downloaded_file` means at least one successful file exists.
- `rejected_track` means at least one rejection occurred.
- Redis progress means a download may be in progress.

This makes it hard to answer the key question from `IDEAS.md`: why did a specific track not download?

### Design

Create a durable `track_runs` or `track_state` table keyed by `search_items.id` and the current run identifier. Persist a state machine:

- `pending`
- `searching`
- `candidates_found`
- `judging`
- `download_queued`
- `downloading`
- `downloaded`
- `no_candidates`
- `rejected_low_score`
- `rejected_not_music`
- `banned`
- `retrying`
- `failed_after_retries`
- `cancelled`
- `internal_error`

Suggested columns:

- `id`
- `run_id`
- `search_item_id`
- `state`
- `reason`
- `attempt_count`
- `candidate_count`
- `selected_judge_submission_id`
- `last_error`
- `started_at`
- `updated_at`
- `finished_at`

Use a unique index on `(run_id, search_item_id)`.

### Concrete Changes

1. Add a Diesel migration.
   - Add a PostgreSQL enum or text-check constraint for lifecycle states.
   - Add `track_runs` with foreign keys to `search_items` and optionally `judge_submissions`.
   - Add indexes for dashboard queries:
     - `(run_id, state)`
     - `(search_item_id)`
     - `(updated_at)`

2. Update Diesel schema and models.
   - Add `TrackRunRow`, `NewTrackRunRow`, and update helpers.
   - Add a `RuntimeTrackState` enum near `context_manager.rs` or in a new `internals/state` module.

3. Update `DatabaseManager::load_item_to_database`.
   - On `Track::Query`: upsert `pending` then `searching`.
   - On `Track::Result`: increment candidate count and set `candidates_found`.
   - On accepted judge submission: set `download_queued`.
   - On download start: set `downloading`.
   - On `Track::File`: set `downloaded` with `finished_at`.
   - On no candidates: set `no_candidates`.
   - On retry: set `retrying`, increment attempts.
   - On final rejection: set the matching terminal failure.
   - On task error: set `internal_error` where the failing task can be tied to a track.

4. Add an explicit event for search exhaustion.
   - `track_search_task` currently logs `Exited because consecutive empty results`.
   - Add a `Track::SearchExhausted(SearchItem)` or `Track::NoCandidates(SearchItem)` event when no new submissions were emitted for a track.
   - Persist it as `no_candidates` only if the track has no candidate submissions.

### Tests

- Migration test through Diesel if available.
- Unit tests for state transitions.
- Database tests for idempotent upserts.
- API test verifying a searched-but-empty track returns `NO_CANDIDATES` rather than staying `SEARCHING`.

### Acceptance Criteria

- Every queried track has one current row in `track_runs`.
- Every run can report terminal and non-terminal counts directly from `track_runs`.
- The dashboard no longer needs to infer primary status from unrelated table existence.

## Phase 3: Enforce One Successful Download Per Track

### Problem

The log analysis found 33 downloaded events but only 25 unique downloaded tracks. If the goal is one file per Spotify/source track, successful completion should cancel or ignore other candidates for the same track.

### Design

Use both in-memory and database-level guards:

- In memory: prevent scheduling a second download for a track that is `download_queued`, `downloading`, or `downloaded`.
- In database: enforce at most one successful `downloaded_file.track`.
- In task flow: once `Track::File` is processed, mark the track terminal and reject/ignore any later `Downloadable` events for that track.

### Concrete Changes

1. Add a unique partial index.

   ```sql
   CREATE UNIQUE INDEX downloaded_file_track_uidx
     ON downloaded_file(track)
     WHERE track IS NOT NULL;
   ```

2. Replace the current `HashSet<SearchItem>` download state in `run_cycle`.
   - Use a richer in-memory map keyed by `track_id`:

   ```rust
   enum InMemoryTrackStatus {
       Searching,
       DownloadQueued,
       Downloading,
       Downloaded,
       Failed,
   }
   ```

3. Check the persistent lifecycle state before scheduling downloads.
   - If already terminal downloaded, reject as `AlreadyDownloaded` or silently ignore duplicate candidates.
   - Prefer a distinct `DuplicateAfterSuccess` internal metric rather than polluting user-visible rejected rows.

4. Stop retries after success.
   - When handling `Track::Retry`, first check whether the track has since reached `downloaded`.
   - If yes, discard the retry.

### Tests

- Database test proves the unique track download index blocks duplicates.
- Run-cycle test where two accepted candidates arrive for the same track and only one download task is scheduled.
- Retry test where a late retry after success is discarded.

### Acceptance Criteria

- Re-running the log scanner shows zero duplicate successful downloads per track.
- Dashboard completed count equals unique completed tracks, not downloaded file event count.

## Phase 4: Normalize Peer Failures and Retry Policy

### Problem

The logs contain many expected peer failures:

- connection timed out
- connection refused
- no route to host
- download status receive timeout

These are normal for P2P downloads, but currently they blend with internal errors and do not produce a clear final per-track explanation.

### Design

Introduce structured failure reasons and bounded retry policy:

- `peer_timeout`
- `peer_refused`
- `peer_unreachable`
- `download_stalled`
- `queued_too_long`
- `hard_deadline`
- `library_error`
- `internal_error`

Retry based on candidate and track attempt counts:

- Retry a different candidate for the same track when available.
- Re-search only after candidate exhaustion or stale results.
- Stop after a configurable max attempt count.

### Concrete Changes

1. Replace the hard-coded single retry in `run_cycle`.
   - Add config:
     - `MAX_TRACK_RETRIES`
     - `MAX_CANDIDATE_RETRIES`
     - `DOWNLOAD_HARD_DEADLINE_SECS`
     - `DOWNLOAD_MAX_QUEUED_SECS`
     - `DOWNLOAD_MAX_NO_PROGRESS_SECS`

2. Extend `RetryRequest`.
   - Include failure reason.
   - Include attempt number and maybe candidate identity.
   - Include whether retry should use another candidate or re-run search.

3. Update `download_track`.
   - Map `DownloadStatus::Failed`, `TimedOut`, queue timeout, no-progress timeout, and status receive errors to structured failure reasons.
   - Avoid logging expected peer failure paths at `error`; use `warn` or `info` with structured fields.
   - Reserve `error` for internal failures such as DB/Redis/write/path conversion failures.

4. Persist failure reasons.
   - Store final failure reason in `track_runs.reason`.
   - Store candidate-level failure rows if needed for debugging. This can be a later migration if `retry_request` is enough.

### Tests

- Unit tests for failure reason mapping.
- Unit tests for retry decision policy.
- Integration-style test for failed candidate leading to retry and then terminal `failed_after_retries`.

### Acceptance Criteria

- Logs distinguish expected peer churn from app bugs.
- API can explain a failed track without requiring raw log inspection.
- Retry limits are configurable and visible in startup logs.

## Phase 5: Improve Search Outcome Reporting

### Problem

Search currently sends candidate submissions as they appear and logs when consecutive empty rounds exceed the cutoff. The run does not clearly persist whether a track had zero candidates, weak candidates, filtered candidates, or a later download failure.

### Design

Make search produce a final summary event per track:

```rust
struct SearchSummary {
    track: SearchItem,
    emitted_candidates: usize,
    total_files_seen: usize,
    cutoff_reason: SearchCutoffReason,
}
```

Possible cutoff reasons:

- `consecutive_empty_results`
- `timeout`
- `cancelled`
- `client_error`

### Concrete Changes

1. Add `Track::SearchSummary(SearchSummary)`.
2. Count emitted candidates inside `track_search_task`.
3. Persist candidate count and search cutoff reason in `track_runs`.
4. Update API candidate/status views.
   - A track with zero candidates should show `NO_CANDIDATES`.
   - A track with candidates but no acceptable score should show `REJECTED_LOW_SCORE`.
   - A track with candidates and active candidate evaluation should show `FILTERING` or `JUDGING`.

### Tests

- Search task emits summary after cutoff.
- Summary with zero emitted candidates updates state to `no_candidates`.
- Summary with candidates does not overwrite later download states.

### Acceptance Criteria

- The system can answer “searched but found nothing” versus “found candidates but rejected them.”

## Phase 6: API and Frontend Status Overhaul

### API Changes

Update `convert-invert/src/bin/trigger_server/api.rs` to query `track_runs` as the primary status source.

1. `GET /api/stats`
   - Count states from `track_runs`.
   - Report:
     - total tracks
     - searching
     - candidates found
     - downloading
     - completed
     - failed
     - no candidates
     - retrying
     - internal errors
   - Keep old fields for frontend compatibility until the UI is updated.

2. `GET /api/playlists/{id}`
   - Return lifecycle state, reason, attempts, candidate count, score, progress, and last update timestamp.
   - Preserve current pagination.

3. `GET /api/tracks/{id}/candidates`
   - Include candidate retry/failure information if persisted.

4. `GET /api/workers/status`
   - Include:
     - active worker count
     - active task counts by label if available
     - Redis queue length
     - failed/retry counts
     - current run ID or run IDs

### Frontend Changes

Update the current React dashboard without a full redesign.

1. `convert-invert-frontend/types.ts`
   - Add new track statuses.
   - Add fields for reason, attempts, candidate count, and updated time.

2. `TrackRow.tsx`
   - Display explicit lifecycle state.
   - Show reason text for terminal failures.
   - Show attempts/retry indicator when applicable.

3. `StatsHeader.tsx`
   - Add counters for no candidates, retrying, and internal errors.

4. `SimilarityModal.tsx` and `CandidateDetailModal.tsx`
   - Surface selected candidate, failures, and retry history if API data is available.

5. `WorkersView.tsx`
   - Show queue length, failed count, and worker/run IDs already returned by the backend.
   - Add warning styling for internal errors only, not normal peer failures.

### Tests

- TypeScript compile.
- Frontend rendering tests if available.
- Manual browser pass against seeded states.

### Acceptance Criteria

- The dashboard shows why tracks are pending or failed.
- Operators no longer have to infer lifecycle state from candidate count or raw Jaeger logs.

## Phase 7: Observability and Metrics

### Logging

Standardize structured fields:

- `run_id`
- `worker_id` or worker username
- `track_id`
- `track_name`
- `artist`
- `candidate_username`
- `candidate_filename`
- `task_label`
- `attempt`
- `failure_reason`

Logging level policy:

- `debug`: routine scheduling and progress chatter.
- `info`: state transitions, worker start/stop, run start/finish.
- `warn`: expected peer/download failures that cause retry or rejection.
- `error`: app bugs, persistence failures, task panics, channel/JoinSet inconsistencies.

### Metrics

If the project keeps Jaeger only, add span fields consistently. If a metrics backend is available later, expose:

- searches started/completed
- candidates emitted
- candidates accepted/rejected
- downloads started/completed
- peer failures by reason
- task panics/errors
- duplicate candidates ignored
- duplicate downloads prevented
- run duration

### Acceptance Criteria

- A future log analysis can group by `track_id` and reconstruct the lifecycle without guessing.
- Expected P2P failures are visible but do not look like application crashes.

## Phase 8: Cleanup and Hardening

1. Remove obsolete status inference once the frontend uses `track_runs`.
2. Remove `Track::TaskComplete` if no longer used.
3. Audit Redis keys.
   - Namespaced keys by `run_id`.
   - Add TTLs for progress keys after terminal state.
   - Avoid stale Redis progress making completed or failed tracks look active.

4. Audit worker lifecycle.
   - `WorkerSupervisor::status` currently drops finished handles but does not expose exit reasons.
   - Store worker exit summaries in memory or Redis.
   - Surface abnormal exits in `/api/workers/status`.

5. Document production host requirements.
   - Redis memory overcommit warning.
   - Jaeger v1 end-of-life warning.
   - File descriptor/network limits for Soulseek downloads.

## Suggested Implementation Order

1. Phase 0 baseline and log scanner.
2. Phase 1 JoinSet-based run-cycle ownership.
3. Phase 3 duplicate-download prevention.
4. Phase 5 search summary events.
5. Phase 2 persistent lifecycle state.
6. Phase 4 retry/failure normalization.
7. Phase 6 API/frontend status update.
8. Phase 7 observability pass.
9. Phase 8 cleanup.

This order intentionally fixes correctness before adding new UI surface area. The lifecycle table is more valuable after the task loop is trustworthy, because otherwise it risks faithfully persisting confused orchestration.

## Validation Matrix

| Area | Command or Method | Expected Result |
| --- | --- | --- |
| Rust formatting | `cargo fmt --check` in `convert-invert` | No formatting diffs |
| Rust unit tests | `cargo test` in `convert-invert` | Unit and integration tests pass |
| Rust compile | `cargo check` in `convert-invert` | Backend compiles |
| Frontend compile | `npm run build` in `convert-invert-frontend` | Frontend compiles |
| Migration apply | Diesel migration run against dev DB | New lifecycle tables/indexes exist |
| Baseline run | Start workers against known playlist | No task-completion channel errors |
| Duplicate check | Log scanner | Zero duplicate successful downloads per track |
| State coverage | SQL count of tracks without `track_runs` row | Zero for active run |
| Terminal coverage | SQL count of old run tracks in non-terminal state | Zero unless run was cancelled |
| UI smoke test | Open dashboard | Statuses and counts match API |

## Rollback Strategy

- Keep migrations reversible where possible.
- Add lifecycle state as additive schema first; do not remove old inference paths until validated.
- Keep API response fields backward-compatible during the frontend transition.
- Gate new retry policy values with environment defaults matching current behavior at first.
- If JoinSet refactoring destabilizes runs, temporarily keep the old code path behind a compile-time or environment flag while debugging.

## Open Questions

1. Is the intended product behavior exactly one downloaded file per Spotify track, or are multiple versions/remixes acceptable?
2. Should a worker shutdown drain current downloads, abort immediately, or use a bounded graceful timeout?
3. Should `AlreadyDownloaded` appear as a user-visible rejection, or should duplicate candidates after success be hidden as internal no-ops?
4. Should lifecycle state be scoped to a `run_id`, playlist ID, or global track identity?
5. What is the desired retry budget for normal P2P instability?
6. Should failed tracks be automatically re-queued by the leader, or should retry be an explicit user action after the first run?

## Definition of Done

The overhaul is complete when a full playlist run can be inspected from the dashboard or API and every track has a clear state and reason, with no normal `channel closed` completion errors, no duplicate successful downloads per track, bounded retry behavior, and logs that distinguish expected peer failures from internal application failures.
