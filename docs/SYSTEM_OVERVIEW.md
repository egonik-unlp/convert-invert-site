# System Overview & Data Flow

## Purpose
`convert-invert-site` is a bridge between Spotify and the Soulseek P2P network. Its primary goal is to automate the process of finding and downloading high-quality matches for tracks in a Spotify playlist.

## Core Technologies
- **Backend**: Rust (Actix-web, Diesel)
- **Frontend**: React 19 (Vite, Tailwind CSS, shadcn/ui)
- **Soulseek engine**: Python (`aioslsk`) — search, download and share on one login
- **Judge (optional)**: a fine-tuned SmolLM served by ollama, fronted by an in-process rule engine
- **Infrastructure**: PostgreSQL (Persistence), Redis (Task Queue & Progress), Jaeger (Tracing)

## High-Level Architecture
The system is divided into three main services:
1.  **Backend (Rust)**: The brain of the operation. It orchestrates runs, judges candidates, owns persistence and Spotify, and exposes a REST API for the frontend. All Soulseek I/O is delegated to the engine over HTTP.
2.  **Frontend (React)**: A real-time dashboard for monitoring workers, playlists, individual tracks, and the judgement log.
3.  **Soulseek engine (`slsk`)**: An `aioslsk`-based service that does search, download **and** share on a single login, using server-brokered peer connections so transfers work from behind NAT/CGNAT.

The judge runs **inside** the backend. When `JUDGE_BACKEND=smol` it calls out to an ollama host for the candidates its rule engine cannot settle on its own; there is no separate judging microservice in the compose stack.

---

## Track Lifecycle & Data Flow

The journey of a track from a Spotify playlist to a local file follows a structured pipeline:

### 1. Ingestion & Chunking
- The user triggers a run for a Spotify playlist via the Frontend/API.
- The Backend fetches the playlist tracks and splits them into **chunks** (default size is 15 tracks).
- These chunks are pushed into a **Redis queue**.

### 2. Worker Assignment
- **Workers** (which can be the same process as the server or separate instances) pull chunks from Redis.
- Each worker initializes its own Soulseek client and begins a **Run Cycle**.

### 3. Search Phase
- For each track in the chunk, the worker sends a search query to the Soulseek network.
- Search results are collected and parsed into **Candidates**.
- The search continues until a cutoff is reached (e.g., a certain number of candidates or consecutive empty results).

### 4. Judging Phase
- Candidates are scored to determine the best match. One judge is active per run, chosen by `JUDGE_BACKEND`:
- **Levenshtein judge** (default): a quick string-similarity check between the query and the filename. Cheap, but cannot tell a track from its remix — as strings they barely differ.
- **Smol judge**: a deterministic rule engine settles ~83% of candidates outright; the rest go to a fine-tuned SmolLM on ollama, which answers with a label (`exact`, `wrong_version`, `wrong_artist`, `different`) rather than a distance. Only `exact` clears the threshold.
- Every verdict — label, model, latency, raw reply, any error — is written to the `judgements` table and surfaced in the dashboard's **Judgements** view.
- The highest-scoring candidate that passes `JUDGE_THRESHOLD` (0.75) is selected for download.

See the [Judges section of the README](../README.md#judges) for the full picture, including switching judges at runtime.

### 5. Download Phase
- The worker requests the file from the Soulseek peer.
- Download progress is reported to **Redis** in real-time and surfaced on the dashboard.
- If a download fails (common in P2P), the system may retry with another candidate or re-search.

### 6. Persistence & Completion
- Once a download completes successfully, the metadata is recorded in **PostgreSQL**.
- The track reaches a **Terminal State** (Downloaded) in the `track_runs` table.
- The dashboard reflects the updated status, and the file is available in the configured downloads directory.
