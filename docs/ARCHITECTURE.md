# System Architecture

This document provides a deep dive into the internal design of `convert-invert-site`, focusing on the Rust backend's organization and orchestration.

## Backend Managers
The backend is organized into specialized "Managers" located in `src/internals/`, each responsible for a specific domain of the system:

- **`ContextManager` (`src/internals/context/`)**: The central orchestrator. It owns the **Run Cycle**, manages the task queue, and coordinates communication between other managers via an internal channel.
- **`SearchManager` (`src/internals/search/`)**: Handles searching the Soulseek network. It manages search queries, parses incoming search results, and applies cutoffs to avoid infinite searching.
- **`JudgeManager` (`src/internals/judge/`)**: Responsible for scoring search candidates, comparing each score against `JUDGE_THRESHOLD` and routing the candidate to download or rejection. Judges are pluggable and selected by `JUDGE_BACKEND`: `Levenshtein` (string similarity) or `Smol` (rule engine + fine-tuned SmolLM on ollama). A `RelativeMi` score is recorded alongside whichever is active but never acted on. Every verdict is captured as a `Judgement` and persisted to the `judgements` table.
- **`DownloadManager` (`src/internals/download/`)**: Manages the actual file transfer from Soulseek peers. It handles the network loop, progress reporting, and local file persistence.
- **`DatabaseManager` (`src/internals/database/`)**: Abstracts PostgreSQL interactions. It handles persistence for search items, judge submissions, and the authoritative track lifecycle state.
- **`WorkerManager` (`src/internals/worker/`)**: Manages the lifecycle of workers, including pulling tasks from Redis and supervising the run cycles.

## Orchestration: The Run Cycle
The core of a worker's activity is the `run_cycle` (implemented in `context_manager.rs`). 

### Task Ownership with `JoinSet`
To ensure reliability and prevent "channel closed" errors, `run_cycle` uses a `tokio::task::JoinSet` to own all spawned tasks (search, judge, download, retry).
- **Explicit Tracking**: Every spawned task is added to the `JoinSet`.
- **Draining**: The `run_cycle` loop selects over both the internal message channel and the `JoinSet`.
- **Completion**: The cycle only exits once the message channel is empty AND all tasks in the `JoinSet` have been joined.

## Infrastructure Roles

### Redis: The Nervous System
- **Task Queuing**: Playlist chunks are stored in Redis, allowing multiple workers to pull and process work concurrently.
- **Progress Tracking**: Real-time download progress is written to Redis, allowing the dashboard to show active progress without heavy database polling.

### PostgreSQL: The Authoritative State
- **Long-term Storage**: Stores metadata for all searched tracks, candidates, and downloaded files.
- **Authoritative Lifecycle**: The `track_runs` table is the single source of truth for the status of a track in a given run (e.g., `searching`, `downloading`, `downloaded`, `failed`).

### Jaeger: Observability
- **Distributed Tracing**: The backend uses OpenTelemetry and Jaeger to track the lifecycle of requests and tasks. This is invaluable for debugging performance bottlenecks and tracing the path of a specific track through the managers.

## The `smol` Judge

When `JUDGE_BACKEND=smol`, judging is a two-stage pipeline inside the backend process:

1. **`judges/rules.rs`** — a deterministic rule engine, ported from the `smol-model-test` repo and developed against all 15,374 real (query, candidate) pairs. A `Gold` verdict is final and short-circuits; `Weak` and `Abstain` fall through. It settles ~83% of candidates with no inference, and the hybrid beats the model alone (96.0% vs 93.6% accuracy on 826 held-out rows). Disable with `SMOL_JUDGE_RULES=0` to measure the model unaided.
2. **`judges/smol.rs`** — an HTTP call to ollama (`SMOL_JUDGE_URL`) for everything the rules did not settle, bounded by a semaphore (`SMOL_JUDGE_CONCURRENCY`) because ollama serves one request at a time per model. On failure, `SMOL_JUDGE_FALLBACK` decides whether the Levenshtein score stands in or the candidate is rejected; either way the error lands on the judgement, so a degraded run is visible rather than silent.

The judge can be switched at runtime via `POST /api/judge`; the override lives in Redis (`judge:backend`, `judge:url`) and applies to the next run.

`judges/smol.rs` and `src/prompt.ts` in `smol-model-test` must render the same prompt — both are tagged `PROMPT_VERSION`, and every stored judgement records the version it was produced under.

## The experimental `llm` module
The `llm` module is a separate Bun/LangChain service. It is **not** part of `docker-compose.yml` and the backend does not call it; it predates the smol judge and is kept only for scoring experiments.
