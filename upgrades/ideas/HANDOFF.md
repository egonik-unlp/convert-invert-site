# Handoff — Code Quality & Aesthetics Overhaul

## Continuation update — 2026-05-22

The interrupted work was continued and the main compile/build risks were resolved.

### Completed in this continuation

- Backend Phase 2 pending work:
  - `download_manager.rs` now uses `db_pool.get_timeout(Duration::from_secs(5))` and `redis_pool.get_timeout(Duration::from_secs(5))` inside the blocking download thread.
  - `context_manager.rs` now has `WorkerTuning::from_env()` with `SEARCH_CONCURRENCY`, `DOWNLOAD_CONCURRENCY`, `QUEUE_CAPACITY`, and `PREFETCH_BUFFER` env overrides. Defaults remain `4`, `7`, `20000`, and `300`.
  - Dedup state is removed on `Track::Retry` and `Track::Reject`, so failed downloads can be retried.
  - Fixed compile errors in `trigger_server/api.rs` Diesel raw SQL binding and in `trigger_server/main.rs` state ownership after moving state into the Actix app factory.
  - Removed unused `HttpMessage` import in auth middleware.
- Backend verification:
  - `cargo check` passes in `convert-invert/`.
  - The first sandboxed `cargo check` failed due DNS; rerun with approved network access succeeded and updated `Cargo.lock` for the new dependencies.
- Frontend Phase 3 setup:
  - Removed Tailwind CDN, Google font link, Material Icons link, inline Tailwind config/style, and React importmap from `convert-invert-frontend/index.html`.
  - Added local Tailwind 3, PostCSS, fontsource Inter/JetBrains Mono, lucide, Radix primitives, and shadcn-style utility dependencies.
  - Added `tailwind.config.ts`, `postcss.config.js`, `index.css`, and `lib/utils.ts`.
  - Added shadcn-style local primitives under `components/ui/`: `button`, `card`, `input`, `badge`, `progress`, `dialog`, `tooltip`, `skeleton`, and `table`.
  - `index.tsx` imports `index.css`.
- Frontend rewrite progress:
  - `api.ts` uses `VITE_API_BASE_URL`, attaches `X-API-Key` from `VITE_API_KEY` to protected endpoints, and gives a clear 401 hint.
  - Added typed `/api/config` fetch via `api.getConfig()`.
  - `types.ts` now uses `TrackStatus.FINALIZING` directly instead of the string-literal union.
  - Added `hooks/useAppConfig.tsx` and `hooks/useTrackStage.ts`.
  - Added `components/ErrorBoundary.tsx`, `EmptyState.tsx`, and `ErrorState.tsx`.
  - Rewrote `App.tsx` around `ErrorBoundary` + `AppConfigProvider`.
  - Rewrote `Sidebar.tsx`, `StatsHeader.tsx`, `TrackRow.tsx`, `SimilarityModal.tsx`, `CandidateDetailModal.tsx`, and `GlobalFooter.tsx` with local shadcn-style primitives and lucide icons.
  - Rewrote `PlaylistsView.tsx` and `WorkersView.tsx` with local shadcn-style primitives and lucide icons.
  - Wired `App.tsx` so the Playlists navigation item shows `PlaylistsView` and can select a playlist or start workers from a manual playlist ID.
  - `SimilarityModal` and `CandidateDetailModal` now use `/api/config`'s `judgeThreshold` instead of hardcoded `0.8` / `0.85`.
  - Fixed the Vite dev blank-screen issue: root-level `api.ts` was being served as `/api.ts`, which matched the `/api` proxy and returned a backend 404 as a JavaScript module. The API client now lives at `lib/api-client.ts`.
  - Fixed the React entrypoint to use named `createRoot` from `react-dom/client`.
  - Added a small boot fallback/error reporter in `index.html` so module startup failures are visible instead of a blank screen.
  - Added a first-class playlist download launcher to `PlaylistsView.tsx`: users can paste a Spotify playlist URL/ID, review worker count/chunk/range settings in a confirm dialog, and launch via `POST /api/workers/start`.
  - `App.tsx` now shows a success notice and switches to Downloads after a successful playlist launch.
  - Fixed the Playlists view runtime UX: the manual Spotify playlist field is now explicitly labelled/focusable, selected playlist fallback art no longer points at a missing `/favicon.svg`, and playlist cards render a stable icon panel when the API does not provide usable cover art.
  - `App.tsx` now preserves the active section in the URL hash, so `http://127.0.0.1:3000/#playlists` opens the playlist launcher directly and refreshes keep the current view.
- Frontend verification:
  - `npm run build` passes in `convert-invert-frontend/`.
  - Headless Chrome screenshot of `http://127.0.0.1:3000/` now shows the rendered dashboard UI.
  - Headless Chrome screenshot of `http://127.0.0.1:3000/#playlists` now shows the patched playlist launcher with the fallback art panel and focused input.
  - Vite dev server was restarted on `http://127.0.0.1:3000/`.
  - `npm install` reported 2 high severity vulnerabilities. `npm audit fix` was intentionally not run because it can make broader dependency changes.

### Still pending / known gaps

- No Lighthouse verification has been done yet.
- Manual backend smoke status: the running Docker API at `http://127.0.0.1:3124` reports `/api/health` as API/DB/Redis/Jaeger online. `/api/config` is still 404 on the running container image, so the frontend uses a compatibility fallback. `/api/workers/start` reaches the Rust API but returns `500 Authenticate Spotify client credentials`.
- A real playlist launch cannot complete until the running API container has valid Spotify and Soulseek credentials (`CLIENT_ID`, `CLIENT_SECRET`, `USER_PASSWORD`). The current container has empty credential values.
- The frontend uses local shadcn-style primitives rather than running the interactive `shadcn init/add` generator, because this repo is a flat Vite app and the needed primitives were small enough to add directly.

This file describes what was completed, what is still pending, and known risks in the
work-in-progress state. Another AI agent should be able to pick up from here without
needing the prior conversation context. The original plan lives at
`/home/gonik/.claude/plans/can-you-diagnose-what-toasty-codd.md`.

## Decisions already made (do not re-litigate)

- **Auth:** static API key in `X-API-Key` header, validated by Actix middleware (done)
- **Secrets:** `.gitignore` + `.env.example` template + README (done)
- **Frontend aesthetic:** full redesign on **shadcn/ui** (requires adding Tailwind, since the project currently has neither — it uses Tailwind via CDN today, which must go)
- **Tests:** explicitly skipped — do not add unit/integration tests

## Project tech baseline

- Rust 2024 edition, Actix-web 4.12, Diesel 2.2 (postgres + r2d2), Tokio 1.48
- React 19 + Vite 6, currently no Tailwind install (uses `cdn.tailwindcss.com`), uses an ESM importmap in `index.html` for React (must be removed)
- Postgres + Redis + Jaeger via `docker-compose.yml`

---

## Phase 1 — Security & secrets ✅ DONE

- `/home/gonik/Documents/git/convert-invert-site/.gitignore` — created (covers .env, target, node_modules, dist, logs)
- `convert-invert/.env.example` — created with placeholders
- `convert-invert-frontend/.env.example` — created (`VITE_API_KEY`, `VITE_API_BASE_URL`)
- `convert-invert/.env` — sanitized (replaced literal password with `CHANGE_ME`)
- `docker-compose.yml` — rewritten to require env vars via `${VAR:?message}` syntax (no defaults for secrets), added `API_KEY` and `ALLOWED_ORIGINS` to the api service, added `VITE_API_KEY` build arg to frontend
- `README.md` — created with quick-start + auth + rate-limit docs

---

## Phase 1.2 — Auth middleware ✅ DONE

- `convert-invert/Cargo.toml` — added deps: `actix-cors = "0.7.0"`, `actix-governor = "0.8.0"`, `subtle = "2.6.1"`, `futures-util = "0.3.31"`
- `convert-invert/src/bin/trigger_server/middleware.rs` — created. Uses `actix_web::middleware::from_fn`, validates `X-API-Key` with `subtle::ConstantTimeEq`, bypasses `/api/health` so orchestrators can probe without the key
- Frontend wiring: **NOT YET DONE** — see Phase 3 below

---

## Phase 1.3 + 1.4 — CORS + rate limit ✅ DONE (in code, not verified)

Configured in `convert-invert/src/bin/trigger_server/main.rs`:
- `actix-cors` reading from `AppConfig.allowed_origins` (parsed from `ALLOWED_ORIGINS` env var, comma-separated)
- `actix-governor`: 30 req/min on `/api` (`seconds_per_request(2)`, `burst_size(10)`), 5 req/min on `/api/workers/start` (`seconds_per_request(12)`, `burst_size(3)`)

---

## Phase 2 — Backend correctness (PARTIAL)

The monolithic `convert-invert/src/bin/trigger_server.rs` was **deleted** and replaced
with a module tree at `convert-invert/src/bin/trigger_server/`:

```
trigger_server/
  main.rs          — entrypoint, middleware wiring, shutdown
  config.rs        — AppConfig + load() reading API_KEY, ALLOWED_ORIGINS, etc.
  state.rs         — AppState (AtomicUsize next_worker_id, watch::Receiver<bool> shutdown)
  errors.rs        — ApiError enum implementing ResponseError
  middleware.rs    — require_api_key (from_fn middleware)
  validation.rs    — StartRequest/StopRequest/PlaylistQuery validators
  workers.rs       — start/stop/status handlers + run_worker + install_shutdown_handler
  api.rs           — health, stats, network, config, playlists, playlist, candidates, logs
```

### Done in the rewrite
- **2.1 Input validation** — `StartRequest.validate()` enforces `worker_count: 1..=32`, `port_base: 10000..=65000`, `chunk_size: 1..=1000`. **Hardcoded Spotify playlist fallback removed** — request now returns 400 if `playlist_id` missing.
- **2.2 Atomic worker IDs** — `AppState.next_worker_id: AtomicUsize`, allocated with `fetch_add(1, Relaxed)`.
- **2.3 Silent worker continue** — now logs `tracing::error!` with truncated payload (500 chars) and run_id before continuing.
- **2.4 Pagination** — `/api/playlists/{id}?limit=50&cursor=N`. `limit` validated 1..=200, `next_cursor` returned when page is full. **VERIFY:** the SQL is built dynamically (`cursor_sql` substitution) — the bind ordering may break. Run a quick `cargo check` and a manual `curl` against `/api/playlists/all` to confirm.
- **2.7 Raw SQL hardening** — `table_count` now returns `ApiError::Internal` on unknown table names instead of silently returning 0.
- **2.8 Threshold consolidation** — `pub const JUDGE_THRESHOLD: f32 = 0.75;` added to `convert-invert/src/internals/judge/judge_manager.rs`. Inline `0.75` replaced with `JUDGE_THRESHOLD`. New `/api/config` endpoint exposes it (and the auth scheme/header).
- **2.9 Graceful shutdown** — `install_shutdown_handler` listens for SIGTERM/SIGINT on Unix, flips a `watch::Sender<bool>`. Actix server runs with `shutdown_timeout(30)`. A separate task awaits the shutdown signal and calls `server_handle.stop(true)`. Workers' `run_worker` loops check `*shutdown.borrow()` between chunks and race their `run_cycle` against `shutdown.changed()`.
- **2.10 Worker liveness** — partially. The existing `retain_mut` in `worker_status` reaps finished `JoinHandle`s. A separate watcher per worker was **not** added — judged unnecessary since the reaping handles panics on next status request. If you want stronger guarantees, spawn a per-worker `JoinHandle.await` task that updates a metric/state when it completes.
- **2.11 Log levels** — demoted to `debug!` in `convert-invert/src/internals/download/download_manager.rs`: lines that previously had `tracing::info!` at "send to download", "Still queued", "Downloaded X of Y", "Rejected non song".
- **2.13 Module split** — done (file tree above).

### NOT DONE — Phase 2 work still pending

These were on the plan but I was interrupted before getting to them.

#### 2.5 DB-write timeout (`download_manager.rs`)
Plan said: "Wrap the `spawn_blocking` future in `tokio::time::timeout(Duration::from_secs(10), ...)`."

**Caveat:** the actual `spawn_blocking` body is the entire download loop, which legitimately takes minutes. Wrapping it in a 10s timeout would break downloads. The correct fix is to use `db_pool.get_timeout(Duration::from_secs(5))` and `redis_pool.get_timeout(Duration::from_secs(5))` for the pool-acquire calls at the top of the spawned thread (currently lines ~115–116 inside the `spawn_blocking` closure: `db_pool.get().context(...)?` and `redis_pool.get().context(...)?`).

**Action:** edit `convert-invert/src/internals/download/download_manager.rs` around lines 115–116. Replace `.get()` with `.get_timeout(Duration::from_secs(5))` for both pools. Make sure `Duration` is in scope (it already is at line 11).

#### 2.6 Dedup race in `context_manager.rs:269-295`
Plan: "Keep the early insert but add a `remove()` in the download-failure branch."

**Action:**
1. Read `convert-invert/src/internals/context/context_manager.rs` around lines 269–295 to see the current `RwLock<HashSet>` insert pattern.
2. Identify the download-result branch (likely a `match` on `Track::Retry` / `Track::Reject`).
3. On failure, re-acquire the write lock and `state.write().await.remove(&key)` so the same track can be retried.

#### 2.12 Magic-number extraction in `context_manager.rs:177-185`
Plan: "New `WorkerTuning` struct with named fields (`search_concurrency`, `download_concurrency`, `queue_capacity`, `prefetch_buffer`); load from env."

**Action:**
1. Read `convert-invert/src/internals/context/context_manager.rs` around lines 177–185 to find the semaphore permits (4, 7) and channel buffer sizes (20000, 300).
2. Create a `WorkerTuning` struct at the top of that file (or in a new submodule):
   ```rust
   pub struct WorkerTuning {
       /// Max in-flight search requests against Soulseek. Soulseek is rate-sensitive;
       /// 4 has worked in practice — raise carefully.
       pub search_concurrency: usize,
       /// Max in-flight downloads. 7 keeps the pipeline full without overwhelming
       /// the host's network or file descriptor budget.
       pub download_concurrency: usize,
       /// Capacity of the work-distribution channel; 20000 is large enough for a
       /// full playlist's worth of items without backpressure.
       pub queue_capacity: usize,
       /// Smaller secondary buffer for downstream stages.
       pub prefetch_buffer: usize,
   }
   ```
3. Load from env (e.g. `SEARCH_CONCURRENCY`, `DOWNLOAD_CONCURRENCY`, etc.) with the existing values as defaults.
4. Replace the literals at lines 177, 184, 185 with field reads.

---

## Phase 3.1-3.2 — Tailwind + shadcn/ui install ❌ NOT STARTED

The frontend currently:
- Loads Tailwind via `<script src="https://cdn.tailwindcss.com">` in `convert-invert-frontend/index.html`
- Loads React via an ESM importmap in the same file (bypasses Vite's bundle)
- Has no `tailwind.config`, no PostCSS, no shadcn

### Plan
1. **Remove the CDN/importmap setup** in `convert-invert-frontend/index.html`:
   - Delete `<script src="https://cdn.tailwindcss.com">`
   - Delete the inline `tailwind.config = { ... }` block
   - Delete the entire `<script type="importmap"> ... </script>` block
   - Move the inline `<style>` (custom scrollbar, body styles) into a new `src/index.css`
2. **Install Tailwind**:
   ```bash
   cd convert-invert-frontend
   npm install -D tailwindcss postcss autoprefixer
   npm install -D @fontsource-variable/inter @fontsource-variable/jetbrains-mono
   npx tailwindcss init -p
   ```
3. **Configure `tailwind.config.ts`** (rename from `.js` if generated as `.js`):
   - `content: ["./index.html", "./**/*.{ts,tsx}"]`
   - `darkMode: "class"`
   - Extend theme with shadcn-compatible CSS variables (see shadcn docs for the `hsl(var(--background))` pattern)
4. **Install shadcn/ui**:
   ```bash
   npx shadcn@latest init
   ```
   - Style: **slate**
   - Base color: slate
   - CSS variables: yes
   - Use a single accent (the plan said electric violet — pick a token like `--accent: 270 95% 65%`)
   - `components.json` should point to `components/ui` and `lib/utils.ts`
5. **Add the shadcn primitives** the rewrite will need:
   ```bash
   npx shadcn@latest add button card dialog dropdown-menu input select tooltip badge progress table tabs toast skeleton scroll-area
   ```
6. **Add icon + utility deps**:
   ```bash
   npm install lucide-react class-variance-authority clsx tailwind-merge
   npm install framer-motion       # for subtle motion
   npm install @tanstack/react-virtual  # only if a playlist may exceed 500 rows
   ```
7. **Wire fonts** in `src/index.css`:
   ```css
   @import "@fontsource-variable/inter";
   @import "@fontsource-variable/jetbrains-mono";
   @tailwind base;
   @tailwind components;
   @tailwind utilities;
   ```
8. **Update `index.tsx`** to import the new CSS file: `import "./index.css";`

---

## Phase 3.3-3.6 — Frontend rewrite ❌ NOT STARTED

### Files to rewrite

| File | What to do |
|---|---|
| `convert-invert-frontend/api.ts` | Add `X-API-Key` header from `import.meta.env.VITE_API_KEY` and `VITE_API_BASE_URL` as base URL. Surface 401s clearly (toast or return typed error). |
| `convert-invert-frontend/types.ts` (line 38) | Replace `status: TrackStatus \| 'FINALIZING'` — add `FINALIZING` to the `TrackStatus` enum and drop the string-literal union. |
| `convert-invert-frontend/App.tsx` | Wrap routes in a new `<ErrorBoundary>` (write a minimal one — class component that catches `componentDidCatch`). Add `<Toaster>` from shadcn at root. |
| `convert-invert-frontend/components/Sidebar.tsx` | Rewrite using shadcn `<Button variant="ghost">` items in a `<nav aria-label="Primary">`. Add active-route highlighting. Use `lucide-react` icons. Sidebar collapses to icons below `md` breakpoint. |
| `convert-invert-frontend/components/TrackRow.tsx` | Convert to shadcn `<TableRow>` with `<Progress>` for the bar (no inline `style={{ width }}`), `<Badge>` for status, `<Tooltip>` for full error messages. Extract the status-derivation logic into a `useTrackStage(track)` hook. |
| `convert-invert-frontend/components/SimilarityModal.tsx` | Convert to shadcn `<Dialog>`. **Remove the hardcoded `0.85` on line 107** — fetch `/api/config` once at app start, store in context or a Zustand store, read `judgeThreshold` here. Update the `c.score >= 0.8` comparison on line 88 to use the same value. |
| `convert-invert-frontend/components/StatsHeader.tsx` | Convert to shadcn `<Card>` grid. |
| `convert-invert-frontend/components/PlaylistsView.tsx` | Use `<Skeleton>` rows while loading. Empty-state + error-state via new `<EmptyState>` / `<ErrorState>` components. |
| `convert-invert-frontend/components/WorkersView.tsx` | Same treatment — shadcn primitives, skeleton loading, empty/error states. |
| `convert-invert-frontend/components/CandidateDetailModal.tsx` | shadcn `<Dialog>` with proper focus trap. |
| `convert-invert-frontend/components/GlobalFooter.tsx` | shadcn-styled footer; verify color contrast. |

### New files to create

- `convert-invert-frontend/src/lib/utils.ts` — shadcn's `cn(...)` helper (`clsx` + `tailwind-merge`)
- `convert-invert-frontend/src/components/ErrorBoundary.tsx`
- `convert-invert-frontend/src/components/EmptyState.tsx`
- `convert-invert-frontend/src/components/ErrorState.tsx`
- `convert-invert-frontend/src/hooks/useTrackStage.ts`
- `convert-invert-frontend/src/hooks/useAppConfig.ts` — fetches `/api/config` once, exposes `judgeThreshold`
- `convert-invert-frontend/src/components/ui/*` — shadcn output (auto-generated)

### Design tokens to use

- **Background:** slate-950 / 50 surface scale (shadcn slate base)
- **Accent:** electric violet — `--accent: 270 95% 65%` (replace the existing lime `#13ec5b` everywhere)
- **Radii:** `--radius: 0.75rem`
- **Type:** Inter Variable (UI), JetBrains Mono Variable (filenames, IDs, codes)
- **Motion:** 150ms ease-out default, framer-motion for dialog and row enter/exit

### Layout polish

- Sticky top bar: playlist switcher (shadcn `<Select>`) + active worker count + start/stop button
- Track table virtualized with `@tanstack/react-virtual` only when >500 rows (this is why backend pagination was added)
- Mobile: sidebar collapses to icons under `md` (`hidden md:flex` swap)

### A11y checklist

- All interactive controls have visible focus rings (shadcn provides; verify)
- Icon-only buttons have `aria-label`
- Color contrast ≥ WCAG AA on both themes — run Lighthouse, target ≥ 95 a11y score

---

## Known risks & things to verify

These need a `cargo check` + `npm run build` pass before they can be called done.

1. **`cargo check` has not been run.** I wrote ~600 lines of new Rust without compiling. Likely issues:
   - `actix_web::middleware::from_fn` exists from 4.5+, should work on 4.12. Confirm the closure signature matches the one in `middleware.rs`.
   - `actix-governor 0.8` API: I used `GovernorConfigBuilder::default().seconds_per_request(N).burst_size(N).finish()`. Confirm method names — they changed between major versions.
   - `actix-cors 0.7` API: `Cors::default().allowed_methods(...).allowed_headers(...).max_age(3600)` and `cors.allowed_origin(origin)` returning Self. Verify.
   - The dynamic SQL in `api.rs::playlist` substitutes `$1` or `$2` for the LIMIT bind depending on whether a cursor is present. Manually trace `query_builder.bind` order — it must match the parameter positions in the rendered SQL string.
   - `tokio::sync::watch` is included in `tokio` features `"full"` (we have it).
   - `subtle::ConstantTimeEq` — the `into()` to `bool` should work, but the manual constant-time length-mismatch path I wrote may not actually be constant-time. If you want to be strict, hash both sides and compare hashes, or use `constant_time_eq` crate which handles different lengths properly.

2. **`workers.rs` still imports `post`** but only `#[post("/stop")]` uses it. The `start_workers` function's `#[post("/start")]` was removed in favor of wiring it via `web::resource("/start").route(web::post().to(...))` in `main.rs` so the per-resource governor wrap works. Confirm no unused import warning, and confirm Actix correctly dispatches.

3. **`api.rs::playlist`** — when `cursor` is `None`, the rendered SQL is `... WHERE 1=1  ORDER BY si.id DESC LIMIT $1` (note the trailing blank where `cursor_sql` was empty). That's syntactically fine. With cursor, it's `... WHERE 1=1 AND si.id < $1 ORDER BY si.id DESC LIMIT $2`. Both should work, but **manually test both branches**.

4. **`main.rs` shutdown task** — the `shutdown_listener.changed().await.is_err()` path returns silently. That's intentional (sender dropped means the program is exiting). Confirm the `loop { if *borrow() { break } changed.await }` pattern actually behaves right — there's a subtle issue where `changed()` returns immediately if the value already changed before the first await. Test by hitting Ctrl-C while a request is in flight.

5. **Frontend `.env.example`** points to `http://localhost:3124`, but the api Dockerfile binds to `0.0.0.0:3124`. Make sure CORS `ALLOWED_ORIGINS=http://localhost:5173` matches the frontend port in docker-compose.

6. **Diesel `r2d2` re-export** — I imported `diesel::r2d2::PoolError` for the `From` impl. Verify it exists in diesel 2.2 (it should — it's been there since 2.0).

7. **Module name collision:** I named a Rust module `config.rs` — but `convert_invert::internals::utils::config::config_manager::Config` is unrelated. There's no collision (different paths), just worth noting.

8. **The handler `api::config` may clash with `crate::config`** in main.rs — verify the call site `.service(api::config)` resolves to the handler function, not the module. If clash, rename the handler to `app_config` or move it under a `pub mod handlers { pub mod config; }` namespace.

## Suggested execution order for the next session

1. **First: `cd convert-invert && cargo check`** — fix any compile errors before doing anything else. Most will be small (import paths, governor API signatures). The earlier the fix, the less rework.
2. Apply the 3 remaining backend tasks (2.5 DB timeout, 2.6 dedup race, 2.12 magic numbers) — these are localized edits in `download_manager.rs` and `context_manager.rs`. Re-run `cargo check`.
3. Apply Phase 3.1–3.2 (install Tailwind + shadcn). Run `npm run dev`, confirm a blank page renders.
4. Apply Phase 3.3–3.6 (component rewrites). Walk through the manual verification list in the plan file.
5. Final: `docker compose up --build`, run the smoke tests:
   - `curl http://localhost:3124/api/stats` → 401
   - `curl -H "X-API-Key: $KEY" http://localhost:3124/api/stats` → 200
   - `curl -X POST -H "X-API-Key: $KEY" -H "Content-Type: application/json" -d '{"worker_count":9999,"playlist_id":"x"}' http://localhost:3124/api/workers/start` → 400
   - Hit `/api/workers/start` 10 times in 60s → 429 after 3
   - Frontend: visible at `localhost:5173`, all views render, mobile breakpoint collapses sidebar

## Files changed so far (cumulative diff for reference)

**Created:**
- `.gitignore`
- `README.md`
- `HANDOFF.md` (this file)
- `convert-invert/.env.example`
- `convert-invert-frontend/.env.example`
- `convert-invert/src/bin/trigger_server/main.rs`
- `convert-invert/src/bin/trigger_server/config.rs`
- `convert-invert/src/bin/trigger_server/state.rs`
- `convert-invert/src/bin/trigger_server/errors.rs`
- `convert-invert/src/bin/trigger_server/middleware.rs`
- `convert-invert/src/bin/trigger_server/validation.rs`
- `convert-invert/src/bin/trigger_server/workers.rs`
- `convert-invert/src/bin/trigger_server/api.rs`

**Modified:**
- `docker-compose.yml` — strict env requirements + API_KEY/ALLOWED_ORIGINS/VITE_API_KEY
- `convert-invert/.env` — sanitized
- `convert-invert/Cargo.toml` — added actix-cors, actix-governor, subtle, futures-util
- `convert-invert/src/internals/judge/judge_manager.rs` — `JUDGE_THRESHOLD` constant
- `convert-invert/src/internals/download/download_manager.rs` — `info!` → `debug!` in hot paths

**Deleted:**
- `convert-invert/src/bin/trigger_server.rs` (replaced by directory module tree)
