# System Architecture

This document provides a deep dive into the internal design of `convert-invert-site`, focusing on the Rust backend's organization and orchestration.

## Backend Managers
The backend is organized into specialized "Managers" located in `src/internals/`, each responsible for a specific domain of the system:

- **`ContextManager` (`src/internals/context/`)**: The central orchestrator. It owns the **Run Cycle**, manages the task queue, and coordinates communication between other managers via an internal channel.
- **`SearchManager` (`src/internals/search/`)**: Handles searching the Soulseek network. It manages search queries, parses incoming search results, and applies cutoffs to avoid infinite searching.
- **`JudgeManager` (`src/internals/judge/`)**: Responsible for scoring search candidates. It uses a pluggable architecture allowing for different scoring strategies, such as the `Levenshtein` judge and the `LLM` judge.
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

## LLM Integration
The `llm` module is a separate Node.js service. The Rust backend interacts with it via a simple HTTP API. This separation allows the LLM service to be scaled independently and uses the best-in-class LangChain/OpenAI ecosystem.
