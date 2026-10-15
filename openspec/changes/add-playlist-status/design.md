# Design: add-playlist-status

## Approach

### Resolver colecciones

Hay un módulo nuevo, `collections`, en el trigger server:

```
resolve(user, kind, id) ─▶ Spotify (token del usuario, spotify_user::access_token_for)
                           playlist: /v1/playlists/{id}/tracks   (cache key: snapshot_id)
                           album:    /v1/albums/{id}/tracks
                           liked:    /v1/me/tracks
                           track:    /v1/tracks/{id}
                       ─▶ Vec<SpotifyTrack { spotify_id, title, artists, album, duration_ms, image_url, isrc }>
```

- Caché en Redis por `(kind, id, snapshot_id)`. Los "Me gusta" se cachean por usuario con TTL de 2 min,
  porque no tienen `snapshot_id`.
- Paginación hacia el frontend con `limit` y `cursor` (offset en la lista de Spotify).
  Los conteos se calculan sobre la lista entera.

### Estado por canción

Una sola query agrega por `track_id` sobre la página de Spotify ids
(`WHERE si.track_id = ANY($1)`), con un índice nuevo `search_items(track_id)`:

| Estado | Regla (por `track_id`, aplicando la precedencia del spec) |
|---|---|
| `owned` | Existe `downloaded_file` para alguna fila de `search_items` con ese `track_id` |
| `downloading` | Hay progreso activo en Redis (misma fuente que hoy usa `graph://node:api::playlist`; `FINALIZING` se muestra como `downloading`) |
| `comparing` | Hay `judge_submissions` sin veredicto final (equivale a `FILTERING`) |
| `searching` | La fila está tomada por un worker sin submissions (equivale a `SEARCHING`) |
| `queued` | La fila pertenece a un pedido y todavía no la tomó ningún worker |
| `failed` | Hay `rejected_track` y no hay intento posterior en curso |
| `missing` | No hay filas |

La inferencia actual de `graph://node:api::playlist` se extrae a una función compartida
`track_states(conn, redis, &[track_id])`, para no tener dos implementaciones.

### Resumen y detalle del juicio

- **Resumen** (en la respuesta de colección, solo para `owned`/`failed`). Una query lateral por
  `track_id` toma la última fila de `search_items` y hace join con su `downloaded_file`, el
  `judge_submission` elegido y el juicio con `label` (el que decide, como hoy en `graph://node:api::candidates`).
  - `uncertain` = `label != 'exact'` o `score < JUDGE_UNCERTAIN_BELOW` (env, default 0.75).
  - Para `failed`: `candidatesChecked` y `topLabel` (el más frecuente).
- **Detalle.** `GET /api/tracks/by-spotify/{spotifyId}/judging` resuelve la última fila de `search_items`
  y reusa `graph://node:api::track_report` / `graph://node:judgements_by_submission`, que ya devuelven
  la consulta, los candidatos, los veredictos por juez y el `raw`. Agrega `chosen` comparando contra
  `downloaded_file`. No es solo para admins: el texto del juez no tiene datos sensibles.

### Pedidos

Migración:

| Tabla / columna | Contenido |
|---|---|
| `download_requests` | `id`, `user_id`, `source_kind`, `source_id`, `source_name`, `options` (jsonb), `created_at` |
| `search_items.request_id` | Nullable, FK a `download_requests` |
| `manual_accepts` | `id`, `track` (FK `search_items`), `downloadable_file`, `user_id`, `created_at` |

Flujo de `POST /api/requests`:

1. `collections::resolve` con el token del usuario.
2. `track_states` → filtra a `missing` + `failed` (y a `trackIds` si vino).
3. Si `extendCount`: `nexttrack::shared_model().extend(seeds, n, …)` con las seeds ya resueltas.
   Se refactoriza `graph://node:QueryManager::fetch_extension` para separar "fetch de seeds" de "extender".
4. Crea `download_requests` y llama a `WorkerSupervisor::start` con
   `WorkerStartOptions { tracks: Some(PreResolved { name, items }), request_id, … }` y defaults de
   `WorkerTuning`/`AppConfig`.
   - En `graph://node:WorkerSupervisor::start`, si viene `tracks`, se saltea `QueryManager` y se pasa
     directo a `persist_search_items` (que ahora escribe `request_id`).
   - El `download_subdir` sale de `source_name`; para "Me gusta" es `"{Tus me gusta} - {display_name}"`.
5. Responde `{ requestId, queued }`.

Orden de la cola: FIFO por `request_id` y después por posición en la colección. Las corridas nuevas se
suman a los workers existentes como hoy (el motor aioslsk ya soporta varios workers).

### Cola

`GET /api/queue` extiende lo que hoy hace `graph://node:api::activity`:

- agrega `queued` (filas con `request_id` todavía no tomadas);
- agrega `requestedBy { id, name, avatarUrl }` por ítem (join `search_items.request_id → download_requests.user_id → users`);
- `/api/activity` queda como alias para la UI actual.

### "Usar igual"

Spike: hoy el pipeline elige el candidato con el juez y descarga desde
`graph://community:download`. El plan es:

1. Insertar un `judgements` con `judge = 'manual'`, `accepted = true`, `label = 'exact'` y `raw` con el user.
2. Insertar en `manual_accepts`.
3. Encolar en Redis el `downloadable_file` puntual por el mismo camino que usan los retries
   (`retry_request`).

Si el spike muestra que el camino de retries no sirve para un archivo puntual, este requirement se
separa en su propio change y la UI esconde el botón.

### Decisiones tomadas al implementar

- **Una fila por canción.** `search_items.track_id` ya es `UNIQUE` (migración `stabilize_uniqueness`), así que
  no hay "varias filas por track". La precedencia del spec se aplica entre señales (archivo, progreso en Redis,
  marcador de actividad, pedido pendiente, rechazos), no entre filas. No hizo falta el índice nuevo.
  `playlist_id`/`playlist_name`/`request_id` de la fila reflejan el último pedido que la tocó.
- **"En cola" sin tocar los workers.** Al crear un pedido, cada canción recibe un marcador `req:pending:{spotifyId}`
  en Redis (`request_id`, rechazos al momento de encolar, posición; TTL 24 h). Cuenta como `queued` solo si el
  pedido sigue vivo (algún worker con run id `req{id}-N`) y no apareció un rechazo nuevo desde que se encoló.
  Los rechazos viejos no se borran, así que comparar el conteo es lo que distingue "reintento en cola" de
  "falló otra vez".
- **Cada pedido tiene su propia cola** (`dl:chunk_queue:req{id}:{chunk}`) y sus propios workers; pedidos
  concurrentes no se pisan. El tag de biblioteca sigue siendo el id de Spotify (`liked{userId}` para Me gusta)
  y la carpeta es el nombre de la colección (`Liked Songs - {nombre}` para Me gusta).
- **`since` es un token, no un timestamp.** Cada respuesta guarda en Redis (`collsnap:{token}`, 3 min) los ids
  y la firma del estado de cada canción. El poll siguiente devuelve solo `changes` y un token nuevo. Si el token
  venció o es de otra persona/colección, se responde la página completa.
- **"Usar igual" sí tiene camino.** El pipeline acepta `Track::Downloadable(JudgeSubmission)`, que salta
  búsqueda y juez y agenda la selección del candidato. `WorkerSupervisor::start_forced_download` corre un
  worker con cola vacía que procesa solo eso. Se registra un juicio `judge = 'manual'` (con quién lo eligió en
  `raw`), una fila en `manual_accepts` y un pedido de una canción para que la cola muestre quién lo pidió.
- **`/api/activity` queda igual** para la UI actual. `GET /api/queue` es el reemplazo con `queued` y
  `requestedBy`, agrupado en `downloading` / `comparing` / `searching` / `queued`.
- **La consulta mostrada en el detalle** es la real del search manager: `"{título} - {artista}"`, y en la
  segunda pasada relajada solo el título.
- **Playlists se leen de `/v1/playlists/{id}/tracks`.** Si Spotify mueve ese endpoint, el resolver es el
  único lugar a tocar.

## Archivos a modificar

| Archivo | Cambio |
|---|---|
| `convert-invert/migrations/<nueva>` | `download_requests`, `manual_accepts`, `search_items.request_id`, índice `search_items(track_id)` |
| `convert-invert/src/internals/database/schema.rs` | Regenerar |
| `convert-invert/src/bin/trigger_server/collections.rs` (nuevo) | Resolver colecciones, `track_states`, resumen de juicio |
| `convert-invert/src/bin/trigger_server/requests.rs` (nuevo) | `POST /api/requests`, `GET /api/queue`, `accept` |
| `convert-invert/src/bin/trigger_server/api.rs` | Extraer la inferencia de estado; endpoint de detalle de juicio; `activity` con `requestedBy` |
| `convert-invert/src/bin/trigger_server/main.rs` | Registrar rutas nuevas |
| `convert-invert/src/internals/worker/worker_manager.rs` | `WorkerStartOptions.tracks` / `request_id`; `persist_search_items` con `request_id` |
| `convert-invert/src/internals/query/query_manager.rs` | Separar fetch de seeds de `fetch_extension` |
| `convert-invert-frontend/lib/api-client.ts` | Tipos y métodos nuevos (la UI que los usa es `update-ui-redesign`) |

## Alternativas consideradas

- **Guardar la lista de Spotify de cada colección en la base.** Descartado: se desactualiza, y las
  playlists cambian seguido. Spotify con caché por `snapshot_id` alcanza.
- **Que los workers sigan resolviendo con client credentials.** Descartado: no pueden leer playlists
  privadas ni "Me gusta", y pasar el token del usuario a los workers amplía dónde viven los secretos.
- **Estado por colección en vez de global.** Descartado: el archivo en disco es uno solo; mostrar
  "falta" algo que ya está descargado confunde y genera descargas duplicadas.
- **Detalle del juicio solo para admins.** Descartado: es lo que explica "por qué falló" o "por qué esta
  versión", y eso le importa a quien pidió la canción.

## Riesgos

- Colecciones de miles de canciones: la query de estado con `ANY($1)` sobre 100 ids por página va bien;
  sobre la lista entera (para los conteos) hay que medir. Si hace falta, cachear los conteos por `snapshot_id`.
- Muchos pedidos chicos en paralelo pueden arrancar demasiadas corridas. Si pasa, encolar los pedidos y
  reusar workers vivos en vez de arrancar nuevos.
- `track_id` de Spotify puede cambiar por relinking de mercado. Se ve como "falta" algo que ya está.
  Mitigación posible (fuera de scope): matchear también por ISRC.
