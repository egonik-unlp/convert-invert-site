#!/usr/bin/env bash
# Start a Spotify playlist sync via the running API.
#   zig build sync -Dplaylist=<spotify-url-or-id> [-Dworkers=N] [-Dchunk=N]
# Requires the backend to be up (zig build serve / zig build up).
set -euo pipefail

# Run from the repo root (where .env lives), regardless of caller cwd.
cd "$(dirname "$0")/.."

raw="${1:-}"
workers="${2:-1}"
chunk="${3:-15}"

if [ -z "$raw" ]; then
  echo "usage: zig build sync -Dplaylist=<spotify-playlist-url-or-id> [-Dworkers=N] [-Dchunk=N]" >&2
  exit 1
fi

# Accept a full URL, a spotify: URI, or a bare id.
id=$(printf '%s' "$raw" | sed -E 's#.*/playlist/##; s#^spotify:playlist:##; s#[?&].*$##')

if [ ! -f .env ]; then
  echo "no .env found in $(pwd); run from the project root" >&2
  exit 1
fi
key=$(grep -E '^API_KEY=' .env | cut -d= -f2-)
port=$(grep -E '^API_PORT=' .env | cut -d= -f2-)
port="${port:-3124}"
if [ -z "$key" ]; then echo "API_KEY not set in .env" >&2; exit 1; fi

echo "Starting sync: playlist=$id workers=$workers chunk=$chunk -> http://localhost:${port}"
curl -fsS -X POST "http://localhost:${port}/api/workers/start" \
  -H "X-API-Key: ${key}" \
  -H 'Content-Type: application/json' \
  -d "{\"worker_count\":${workers},\"playlist_id\":\"${id}\",\"chunk_size\":${chunk}}"
echo
