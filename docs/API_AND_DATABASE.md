# API, Database & Observability Reference

This document provides technical details for interacting with the system and understanding its persistence and observability layers.

## REST API

The backend API is served by the `trigger_server` binary. All endpoints (except `/api/health`) require an `X-API-Key` header.

### Core Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/api/health` | `GET` | Health check. |
| `/api/stats` | `GET` | Summary statistics (total tracks, completed, downloading, etc.). |
| `/api/network` | `GET` | Soulseek network status. |
| `/api/playlists` | `GET` | List active runs/playlists. |
| `/api/playlists/all` | `GET` | History of all runs. |
| `/api/tracks/{id}/candidates` | `GET` | Candidates found for a specific track, each with every judge's verdict. |
| `/api/judgements` | `GET` | Judgement log, newest first, plus a summary over the same filters. Query: `limit`, `cursor`, `judge`, `label`, `accepted`. |
| `/api/config` | `GET` | Judge threshold, effective judge (backend/model/url/source), and worker tuning. |
| `/api/judge` | `POST` | Switch the judge at runtime: `{"backend": "smol"\|"levenshtein", "url": "http://…"}`. Applies to the next run; a run already in flight keeps the judge it started with. |
| `/api/judge/reset` | `POST` | Drop the override; revert to the judge the deployment configures. |
| `/api/logs` | `GET` | System logs. |
| `/api/workers/status` | `GET` | Status of active workers and their current tasks. |
| `/api/workers/start` | `POST` | Start a new worker run for a playlist. |
| `/api/workers/stop` | `POST` | Stop active workers. |

### Authentication
Requests must include the `X-API-Key` header, matching the `API_KEY` environment variable.

---

## Database Schema

The system uses PostgreSQL for persistence. Below are the key tables:

### `search_items`
Stores the original track information from Spotify.
- `id` (Primary Key)
- `track`, `artist`, `album`
- `spotify_id`

### `judge_submissions`
Stores candidates found on Soulseek and their scores.
- `id` (Primary Key)
- `track_id` (Foreign Key to `search_items`)
- `filename`, `username`, `size`
- `score` (the active judge's score; see `judgements` for *why* it got that score)
- `relative_mi_score` (experimental, recorded but never acted on)

### `judgements`
One row per (candidate, judge) verdict — *why* a candidate got its score, which
`judge_submissions.score` alone cannot say.
- `id` (Primary Key)
- `submission` (Foreign Key to `judge_submissions`, `ON DELETE CASCADE`)
- `judge` (`levenshtein` | `smol-judge`)
- `model`: the model that answered. A `+rules` suffix (e.g.
  `eduardogonik/smol-judge:c200-q8+rules`) means the deterministic rule engine
  settled it outright and no inference ran — which is how the two stages of the
  `smol` judge are told apart after the fact.
- `label` (`exact` | `wrong_version` | `wrong_artist` | `different`; null for judges that only produce a number)
- `score`, `accepted`, `latency_ms`
- `prompt_version`: the prompt contract the verdict was produced under
- `raw`: the judge's literal reply. For a rule-settled verdict this is
  `{"label":"exact","rule":"R4_exact"}` — the rule that fired, by name.
- `error`: set when the judge failed and a fallback score stood in
- `created_at`
- Unique on `(submission, judge)`: a re-judge replaces the previous verdict, and
  re-sending an identical one is a no-op, so `created_at` means "when the judge
  last changed its mind".

### `downloaded_file`
Metadata for successfully downloaded files.
- `id` (Primary Key)
- `track_id` (Foreign Key to `search_items`)
- `filename`, `path`

### `track_runs` (The State Machine)
The authoritative source for a track's status in a specific run.
- `id` (Primary Key)
- `run_id`, `track_id`
- **`state`**: `pending`, `searching`, `downloading`, `downloaded`, `no_candidates`, `failed`, etc.
- `reason`: Explanation for the state (e.g., "consecutive empty results", "peer timeout").

---

## Observability

### Jaeger (Tracing)
The system is instrumented with OpenTelemetry. You can view detailed traces of every manager interaction and Soulseek request by visiting the Jaeger UI (default port `:16686`).

### `analyze_run_log` Utility
Located in `src/bin/analyze_run_log.rs`, this tool scans worker logs to provide a reliability summary.
- **Usage**:
  ```bash
  cd convert-invert
  cargo run --bin analyze_run_log -- ../workerlogs.log
  ```
- **Metrics**: Reports on channel closures, listener bind panics, DB pool timeouts, and unique download success rates.

### Structured Logging
The backend uses `tracing` for structured logging. Log levels are used consistently:
- `ERROR`: Application bugs or persistence failures.
- `WARN`: Expected P2P instability (timeouts, disconnects).
- `INFO`: Significant state changes (worker start, track completed).
- `DEBUG`: Detailed internal scheduling info.
