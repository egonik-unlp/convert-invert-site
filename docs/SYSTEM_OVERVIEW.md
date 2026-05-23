# System Overview & Data Flow

## Purpose
`convert-invert-site` is a bridge between Spotify and the Soulseek P2P network. Its primary goal is to automate the process of finding and downloading high-quality matches for tracks in a Spotify playlist.

## Core Technologies
- **Backend**: Rust (Actix-web, Diesel, `soulseek_rs`)
- **Frontend**: React 19 (Vite, Tailwind CSS, shadcn/ui)
- **LLM Service**: Node.js/TypeScript (LangChain, OpenAI GPT-4o-mini, Bun)
- **Infrastructure**: PostgreSQL (Persistence), Redis (Task Queue & Progress), Jaeger (Tracing)

## High-Level Architecture
The system is divided into three main services:
1.  **Backend (Rust)**: The brain of the operation. It manages the Soulseek connection, searches for tracks, judges candidates, and handles downloads. It also exposes a REST API for the frontend.
2.  **Frontend (React)**: A real-time dashboard for monitoring the status of workers, playlists, and individual tracks.
3.  **LLM Service**: A microservice that uses large language models to provide advanced judging of search results, ensuring the best possible match is selected based on more than just string similarity.

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
- Candidates are scored to determine the best match.
- **Levenshtein Judge**: Performs a quick string-similarity check between the query and the filename.
- **LLM Judge**: (Optional/Secondary) Sends the query and candidate details to the LLM Service for a more nuanced evaluation (e.g., matching album names, detecting live/remix versions).
- The highest-scoring candidate that passes a threshold is selected for download.

### 5. Download Phase
- The worker requests the file from the Soulseek peer.
- Download progress is reported to **Redis** in real-time and surfaced on the dashboard.
- If a download fails (common in P2P), the system may retry with another candidate or re-search.

### 6. Persistence & Completion
- Once a download completes successfully, the metadata is recorded in **PostgreSQL**.
- The track reaches a **Terminal State** (Downloaded) in the `track_runs` table.
- The dashboard reflects the updated status, and the file is available in the configured downloads directory.
