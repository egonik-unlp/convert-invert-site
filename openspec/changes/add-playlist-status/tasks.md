# Tasks: add-playlist-status

Ver design.md para el approach técnico. Requiere `add-spotify-login` aplicado.

## Spike

- [x] "Usar igual": confirmar si el camino de `retry_request` puede descargar un `downloadable_file` puntual; si no, separar el requirement y avisar a `update-ui-redesign`
      (sirve: `Track::Downloadable` salta búsqueda y juez; ver design.md)
- [ ] Medir la query de estado sobre una colección de ~1.000 canciones

## Backend

- [x] Migración: `download_requests`, `manual_accepts`, `search_items.request_id`; regenerar `schema.rs` (el índice ya existía: `track_id` es `UNIQUE`)
- [x] Inferencia de estado por Spotify id (`track_facts` + `derive_state`) con la precedencia definida.
      `api::playlist` sigue con su propia query: se depreca con la UI vieja en vez de tocarla ahora
- [x] `collections.rs`: resolver playlist / álbum / liked / track con el token del usuario, caché por `snapshot_id`, paginación con cursor
- [x] `GET /api/collections/{kind}/{id}` con conteos (incluido `uncertain`) y `since` para polling
- [x] Resumen de juicio por canción (`owned`: label, score, archivo, peer, formato, `uncertain`; `failed`: candidatos revisados, veredicto más frecuente); env `JUDGE_UNCERTAIN_BELOW`
- [x] `GET /api/tracks/by-spotify/{spotifyId}/judging` (reusa `judgements_by_submission`; `track_report` es demasiado pesado: lee trazas de Jaeger) + `chosen`
- [x] Extender a partir de seeds ya resueltas (`requests::extension` llama directo al modelo; `fill_albums` pasó a público, sin tocar `fetch_extension`)
- [x] `WorkerStartOptions.pre_resolved` / `request_id` + `start_forced_download`; `persist_search_items` escribe `request_id`
- [x] `POST /api/requests` (filtrado, selección, opciones, defaults del server, overrides solo para admin, carpeta de "Me gusta")
- [x] `GET /api/queue` con `queued` y `requestedBy`; `/api/activity` como alias
- [x] `POST /api/tracks/by-spotify/{spotifyId}/accept` (según el resultado del spike)
- [x] Tests: precedencia de estado con varias filas, colección nunca descargada, pedido sin nada para encolar, selección, miembro con `workerCount`, uncertain por label y por score

## Frontend (solo contratos)

- [x] Tipos y métodos en `api-client.ts` para colecciones, detalle de juicio, pedidos, cola y accept

## Validation

- [x] `cargo test` y `cargo clippy` sin errores nuevos
- [x] `npx tsc --noEmit` sin errores
- [ ] Test manual con `curl` y sesión: abrir una playlist privada, pedir lo que falta, ver la cola con el nombre de quien pidió, ver el detalle de juicio de una canción descargada y de una fallida
      (hecho e2e contra Postgres/Redis descartables con la colección cacheada y sesiones sembradas; falta con Spotify real)

## Post-archive

- [ ] `/documenter distill <dated-change-id>`: **auto-ejecutado por `/opsx:archive`**.
      Correr a mano solo si el auto-trigger falló (re-run con el id completo con fecha,
      ej. `2026-10-27-add-playlist-status`). Sincroniza los use-cases `playlist-status` y `download-requests`.
