workerlogs.log
Archivo

I’ll analyze the new workerlogs.log as a fresh run, then compare the main symptoms against the previous run where useful.

I found a different dominant failure in this run: the earlier channel closed completion-report problem is gone, but now the run hits listener port reuse panics plus database write/pool failures.

Pensado durante 2m 31s

I analyzed the new workerlogs.log. This run is different from the previous one: the old Failed to report task completion: channel closed problem is gone, but now the main issues are listener port reuse, DB pool exhaustion, and duplicate downloaded-file inserts.

Main numbers from this run
Metric Count
Log lines 5,135
Playlist tracks fetched 184
Unique track IDs observed in search tasks 155
Search task entries 1,020
“Searching for …” entries 164
“Exited because consecutive empty results” 146
Downloaded file events 17
Unique downloaded tracks 17
Peer disconnects 129
Download status timeouts 9
Retry requests 9
Managed download task failures 5
Listener bind panics 9
DB duplicate track insert errors 4
channel closed errors 0
What improved

The previous run had many:

Failed to report task completion
Caused by:
channel closed

In this new log, I found 0 occurrences of that. That suggests your task-completion reporting problem is likely fixed or at least not triggered in this run.

New biggest problem: listener port already in use

There are 9 panics like:

Failed to bind listener to port: Os {
code: 98,
kind: AddrInUse,
message: "Address already in use"
}

This is serious. It means a worker is trying to start a listener on a port that is still occupied, probably one of:

41000
41001
41002
41003

The pattern looks like this:

worker starts listener on a fixed port,
run cycle finishes or worker restarts,
new worker tries to bind the same port,
old listener/socket has not been fully released,
soulseek-rs-lib panics.

So even though the API process survives, some worker/listener threads are crashing.

Fix direction: do not bind a listener per run cycle unless you guarantee clean shutdown. Better options:

// Conceptually:

- One listener per worker lifetime, not per run cycle.
- Reuse the same logged-in client across cycles.
- If a worker restarts, await listener shutdown before rebinding.
- Treat bind failure as Result/Error, not panic.
- Use dynamic ports or a central port allocator.
  New database problem: pool exhaustion during download

There are 5 managed task failures with:

DB pool in download_track
timed out waiting for connection

This means the download task reached the database-writing step, but could not acquire a DB connection in time. The error appears inside download_track, not during Spotify fetch or search.

Likely causes:

DB pool is too small for your download concurrency.
Each worker has download_permits = 7, and multiple workers/cycles can overlap.
A DB connection might be held while doing slow network/file work.
Panicking/restarting workers may leave async work overlapping longer than expected.

Most important fix: make sure DB connections are acquired only for short DB operations, not held during network download.

Bad shape:

let conn = pool.acquire().await?;
download_file_from_peer().await?;
insert_downloaded_file(conn).await?;

Better shape:

download_file_from_peer().await?;

let conn = pool.acquire().await?;
insert_downloaded_file(conn).await?;

Also consider lowering download_permits or increasing the DB pool size.

Duplicate downloaded-file inserts

Postgres reports:

duplicate key value violates unique constraint "downloaded_file_track_uidx"

The failing statement is:

INSERT INTO downloaded_file (filename, track)
VALUES ($1, $2)
ON CONFLICT (filename)
DO UPDATE SET track = $3

But the violated constraint is on track, not filename. So the query handles duplicate filenames, but not duplicate tracks.

That means this SQL is internally inconsistent with the uniqueness rules:

ON CONFLICT ("filename")

does not protect against:

UNIQUE ("track")

So if two different filenames are found/downloaded for the same track, the second insert can crash.

You probably want one of these instead:

ON CONFLICT ("track") DO NOTHING

or:

ON CONFLICT ("track")
DO UPDATE SET filename = EXCLUDED.filename

depending on your desired behavior.

If your intended invariant is one downloaded file per track, then track should be the conflict target.

Download success rate

The program fetched a playlist with 184 tracks, but this captured run only downloaded 17 unique tracks, about 9.2% of the playlist.

That does not necessarily mean the whole run failed, because the log appears to end while search activity is still happening. But within the captured log, the pipeline is not close to finishing the playlist.

The search layer is active, but many searches end with:

Exited because consecutive empty results
times: 3

I counted 146 of those. This means many tracks either have no usable Soulseek results or your search loop is hitting its empty-result cutoff quickly.

Peer/network failures are expected, but noisy

There are 129 peer disconnects:

Peer error Count
timeout 106
connection refused 20
no route to host 3

This is normal-ish for Soulseek/P2P downloads. These should be treated as routine candidate failures, not as system-level failures.

The real system-level failures are:

listener AddrInUse panics,
DB pool timeouts,
duplicate track insert errors.
My diagnosis

This run is better than the previous one in task-channel lifecycle, but still has worker lifecycle instability.

The central problem now looks like this:

run cycle finishes / worker restarts
↓
same listener port is reused too early
↓
listener bind panic
↓
workers keep logging in/restarting
↓
download tasks overlap
↓
DB pool pressure + duplicate track inserts
Priority fixes

First, fix listener ownership:

one worker = one long-lived listener
do not recreate listener every run cycle
do not reuse a fixed port until the old listener is fully dropped

Second, make downloaded-file insertion idempotent:

INSERT INTO downloaded_file (filename, track)
VALUES ($1, $2)
ON CONFLICT (track) DO NOTHING;

or update on track, not on filename.

Third, prevent DB pool starvation:

do not hold DB connections during network downloads
increase pool size or reduce download_permits
add logs for pool size / checked-out connections

The previous channel closed bug seems fixed, but this run reveals a deeper issue: workers/listeners are not being cleanly lifecycle-managed between run cycles.
