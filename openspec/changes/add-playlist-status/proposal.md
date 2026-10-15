# Proposal: Estado por colección y pedidos de descarga

**Change ID:** add-playlist-status
**Date:** 2026-10-15
**Author:** Eduardo Gonik

## Why

La pregunta que más se hace es "¿qué tiene esta playlist y qué me falta?", y hoy no se puede contestar.
La Library solo muestra canciones que alguna corrida ya tocó; las que nunca se intentaron no aparecen
en ningún lado.

Descargar exige configurar una corrida: workers, chunk, rango. Y cuando una canción falla, el porqué
(los candidatos y los veredictos del juez) vive en un modal aparte o en la pantalla de Judgements.

Para que la UI nueva funcione, el backend tiene que poder contestar tres cosas sobre cualquier colección
de Spotify, incluso las privadas y los "Me gusta":

- en qué estado está cada canción;
- cómo se eligió cada archivo;
- quién pidió qué.

## Scope

- **Capability `playlist-status`** (nueva):
  - endpoint de colección (playlist, álbum, "Me gusta" o canción) que cruza la lista de Spotify con la
    base por Spotify track id;
  - un estado por canción y conteos;
  - para las canciones descargadas, un resumen del veredicto con el que se eligieron;
  - un endpoint de detalle de juicio por canción.
- **Capability `download-requests`** (nueva):
  - pedir la descarga de una colección o de una selección de canciones;
  - el backend resuelve la lista con el token del usuario;
  - queda registrado quién pidió cada cosa;
  - la cola compartida muestra quién pidió qué;
  - reintentar con más intentos.

**Comunidades afectadas:** ver context.md → Nodos afectados (`graph://node:api::playlist`,
`graph://node:WorkerSupervisor::start`, `graph://node:api::activity`, `graph://node:api::candidates`).

**Archivos principales:** `api.rs`, `workers.rs`, `validation.rs`, `worker_manager.rs`,
`query_manager.rs`, migración nueva, `spotify_user.rs`.

## Impact

- **Nuevos endpoints:** `GET /api/collections/{kind}/{id}`, `GET /api/tracks/by-spotify/{spotifyId}/judging`,
  `POST /api/requests`, `GET /api/queue`.
- **`WorkerSupervisor::start`** acepta una lista de tracks ya resuelta. Sin ella sigue funcionando como
  hoy, así que el CLI y `/workers/start` no cambian.
- **`search_items`** gana `request_id`. Hay índice nuevo sobre `track_id`.
- **`/api/activity`** suma quién pidió cada ítem y la lista de en cola.
- **`/api/playlists`** y **`/api/playlists/{id}`** quedan por compatibilidad con la UI actual y se
  deprecan cuando aterrice `update-ui-redesign`.

## Non-goals

- "Mantener sincronizada" (bajar solas las canciones nuevas de una playlist). Queda para otro change;
  la UI lo esconde mientras tanto.
- Repartir la cola de forma justa entre usuarios: es FIFO.
- Cambiar el juez o su taxonomía de veredictos.
- El rediseño visual (`update-ui-redesign`).

## Conflictos con decisiones existentes

Ninguno registrado. **Cambio de modelo:** la unidad de trabajo deja de ser "una corrida con parámetros"
y pasa a ser "un pedido de canciones de una colección". Las corridas siguen existiendo por debajo.
