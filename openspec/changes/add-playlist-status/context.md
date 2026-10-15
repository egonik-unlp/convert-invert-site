# Context: add-playlist-status

> **Fuente del contexto.** El MCP de Graphify no conectó y no hay `graphify-out/`. Los nodos salen de
> leer el código (explore del 2026-10-15) y se citan por ancla de símbolo. Correr
> `/opsx:refresh-context add-playlist-status` cuando exista el grafo. `knowledge/` no existe todavía.
>
> **Depende de** `add-spotify-login`, por el token de Spotify por usuario y los roles.

## Nodos afectados

- `graph://node:api::playlists` / `graph://node:api::playlist`: hoy agrupan `search_items` por
  `playlist_id`. Solo conocen tracks que una corrida ya tocó, así que lo que nunca se intentó no aparece.
- `graph://node:api::candidates` / `graph://node:api::track_report` / `graph://node:judgements_by_submission`:
  ya existe el detalle de candidatos y veredictos por `search_items.id`.
- `graph://node:api::activity`: feed de en vuelo (searching / judging / downloading) sin quién lo pidió.
- `graph://node:WorkerSupervisor::start` (`worker_manager.rs`): resuelve los tracks con client credentials
  (`QueryManager::fetch_with_name` / `fetch_extension`) y después hace `persist_search_items`.
- `graph://node:QueryManager::fetch_extension`: Infinite Playlist; hoy fetchea las seeds por su cuenta.
- `graph://node:workers::start_workers` + `graph://node:StartRequest` (`validation.rs`): disparan una corrida
  por playlist, con parámetros operativos (workers, chunk, rango).
- Tablas: `search_items` (`track_id` = Spotify id), `downloaded_file`, `judge_submissions`, `judgements`,
  `rejected_track`, `downloadable_files`. Progreso en vivo en claves de Redis.

## Archivos relevantes

| Archivo | Rol |
|---|---|
| `convert-invert/src/bin/trigger_server/api.rs` | `playlist(s)`, `candidates`, `track_report`, `activity`, inferencia de estado por track |
| `convert-invert/src/bin/trigger_server/workers.rs` | `start_workers` |
| `convert-invert/src/bin/trigger_server/validation.rs` | `StartRequest` |
| `convert-invert/src/internals/worker/worker_manager.rs` | `WorkerStartOptions`, `start`, `persist_search_items`, `download_subdir` |
| `convert-invert/src/internals/query/query_manager.rs` | Fetch de Spotify y extensión |
| `convert-invert/src/internals/nexttrack/mod.rs` | Modelo de next-track |
| `convert-invert/src/internals/database/schema.rs` | Schema |
| `convert-invert/src/bin/trigger_server/spotify_user.rs` | (de `add-spotify-login`) token por usuario |

## Contexto knowledge

- No hay `knowledge/`. Lo decidido en el explore:
  - El estado de cada canción es **global**: un archivo en disco le sirve a todas las personas que
    tengan esa canción en cualquier playlist.
  - La acción principal es "Descargar las N que faltan" sobre una colección, no configurar una corrida.
  - La UI tiene que mostrar quién pidió cada cosa en la cola compartida.
  - La información del juez tiene que estar a mano por canción: qué archivo se eligió, con qué veredicto,
    y qué se descartó. No solo en una pantalla de admin.
- Maqueta: https://claude.ai/artifact/QtmsGMSjGp6dS8Up6ygpUg

## Riesgos identificados

- **Varias filas de `search_items` por track:** una canción pedida en dos corridas tiene dos filas.
  Hay que agregar con una precedencia clara, y falta un índice sobre `search_items(track_id)`.
- **Corridas concurrentes:** cada pedido arranca workers. Hoy el motor aioslsk tiene un solo login y
  soporta varios workers, pero muchos pedidos chicos en paralelo no se probaron.
- **Rate limit de Spotify:** abrir colecciones grandes (los "Me gusta" pueden tener miles de canciones)
  pagina mucho. Hace falta caché y paginación hacia el frontend.
- **"Usar igual" un candidato rechazado:** no hay camino en el pipeline para forzar la descarga de un
  `downloadable_file` puntual. Necesita un spike.
- **Consumidores de `/workers/start`** (la UI actual y "Resume last run"): mantenerlo durante la transición.
