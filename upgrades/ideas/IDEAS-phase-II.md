I found one especially concrete deployment/code mismatch: the app starts Soulseek listeners on 41000, 41001, etc., but the compose file only publishes the HTTP API port, not the Soulseek listen ports. That can make the service look “up” while P2P transfers are effectively unhealthy.

Respuesta de la aplicación recibida
Pensado durante 2m 50s

Yes. The main failure is not Spotify ingestion. The logs show the playlist is fetched with 184 tracks, but the run produces only 1 downloaded file in your analyzer output. The failures concentrate after ingestion: Soulseek search, peer connectivity, candidate selection, and Docker networking.

Most likely failure points

1. Soulseek listen ports are not exposed in Docker

Your workers start listeners on ports like 41000, 41001, 41002, 41003 in the logs. The backend also computes worker ports as port_base + worker_index, with default WORKER_PORT_BASE=41000 and default WORKER_COUNT=4.

But docker-compose.yml only publishes:

ports:

- "${API_PORT:-3124}:3124"

for the API. It does not publish 41000-41003.

That means the HTTP API can be healthy while the Soulseek P2P listener ports are unreachable from outside the container. In a P2P protocol, that is a very plausible reason for lots of peer failures and very few successful transfers.

A first test would be to publish the worker port range:

api:
ports: - "${API_PORT:-3124}:3124" - "41000-41010:41000-41010"

and also ensure those ports are open on the host firewall/router.

1. The logs show Soulseek-side ban / sharing warnings

Right after login, the logs show automated messages like:

consider sharing the files you get back to the network

from user bkzland.

That strongly suggests at least some peers consider the worker accounts leechers or not properly sharing. Even if this is only one peer, it is a warning sign: Soulseek downloads often depend heavily on peer-specific rules. If the workers are fresh accounts named worker1, worker2, etc., and they do not share anything, many peers may refuse or deprioritize them.

So I would check:

Are worker1, worker2, worker3, worker4 real intended Soulseek accounts?
Are they sharing a folder?
Are they allowed by Soulseek users who require sharing?

The code defaults to worker usernames like worker1, worker2, etc., using WORKER_USERNAME_PREFIX, not necessarily the single USER_NAME you put in the env.

1. Too many searches/download attempts for one Soulseek setup

Defaults are aggressive:

search_concurrency: 4
download_concurrency: 7
worker_count: 4

So in the default web-triggered setup you can get roughly 16 concurrent searches and 28 concurrent downloads across four Soulseek clients/accounts.

For Soulseek, that may be too noisy. It can produce symptoms like:

connection refused
connection timed out
download timeout
empty search results
peer disconnects

Those are exactly the dominant log symptoms. Your analyzer output says: 338 empty-result exits, 30 download timeout warnings, 26 peer disconnects, and only 1 unique downloaded track.

I would test a much smaller setup first:

WORKER_COUNT=1
SEARCH_CONCURRENCY=1
DOWNLOAD_CONCURRENCY=1

Then increase carefully.

1. Search is probably timing out too early for Soulseek

The search manager waits SEARCH_TIMEOUT_SECS, then checks whether new files appeared. The default is 12 seconds, and it exits after more than SEARCH_EMPTY_RESULT_CUTOFF, default 5, consecutive empty checks.

So each search effectively gives Soulseek about a minute-ish before deciding no more useful results are coming. That sounds reasonable in normal HTTP-land, but Soulseek search results can be slow, peer-dependent, and bursty.

The logs repeatedly show:

Exited because consecutive empty results
Relaxed search returned no candidates

I would test:

SEARCH_TIMEOUT_SECS=20
SEARCH_EMPTY_RESULT_CUTOFF=8

especially while reducing concurrency.

1. First acceptable candidate wins, not necessarily the best candidate

The README says the system scores candidates and downloads the best match.

But the code path is more like this:

Search emits candidates as they arrive.
Judge accepts any candidate with score > 0.75.
ContextManager allows only one active download per track using a HashSet<SearchItem>. Other accepted candidates for the same track are rejected as already downloaded/in progress.

That means a merely “good enough” candidate can start downloading before a better candidate appears. If that first candidate is from a bad peer, queued forever, banned, or unreachable, the system may waste the opportunity.

This is probably important because your logs show download retries for plausible matches, but very few completions.

A better strategy would be:

collect candidates for N seconds
score all candidates
sort by score + size + extension + peer availability
try candidate 1
if it fails, try candidate 2
then candidate 3
only then re-search

Right now, retries trigger a relaxed re-search rather than walking the already-found candidate list.

1. Download retry depth is very shallow

When a download fails, DownloadManager returns a Track::Retry. The context manager abandons after retry_attempts >= 1.

In a P2P network, one retry is not much. A track may need several candidate attempts because peers are offline, queued, or refuse transfers.

I would separate:

search retries
candidate retries
download retries

and allow something like:

max_candidates_per_track = 5
max_search_passes = 2
max_download_attempts = 5 7. Worker errors can be swallowed

Inside run_worker, the result of managers.run_chunk(tracks) is ignored:

\_ = managers.run_chunk(tracks) => {}

So if a chunk fails internally, the worker may continue without making the failure obvious at the supervisor level. Your current logs do not show managed task failures, but this makes debugging much harder.

I would change that to log the result:

result = managers.run_chunk(tracks) => {
if let Err(err) = result {
tracing::error!(?err, "run_chunk failed");
}
}
My ranked diagnosis

Most likely:

Docker is not exposing Soulseek listener ports.
Workers are using fresh/multiple accounts that may not be sharing.
Concurrency is too high for Soulseek and causes peer failures/bans/timeouts.
The search timeout/cutoff is too short for noisy P2P search.
The pipeline downloads the first candidate above threshold instead of the best/fallback candidate list.

I would first run one worker, one search, one download, with ports published:

WORKER_COUNT=1
SEARCH_CONCURRENCY=1
DOWNLOAD_CONCURRENCY=1
SEARCH_TIMEOUT_SECS=20
SEARCH_EMPTY_RESULT_CUTOFF=8
WORKER_PORT_BASE=41000

and compose:

ports:

- "${API_PORT:-3124}:3124"
- "41000:41000"

If downloads jump from 1/180 to a much higher number, the biggest issue was networking/concurrency/account reputation, not the matching logic.
