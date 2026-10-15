# Delta Spec: add-playlist-status

**Capability:** playlist-status
**Change:** add-playlist-status

## ADDED Requirements

### Requirement: Colección con estado por canción
`GET /api/collections/{kind}/{id}` (`kind` = `playlist` | `album` | `liked` | `track`) MUST devolver:

- la metadata de la colección (nombre, dueño, portada, duración total);
- las canciones en el orden de Spotify, cada una con título, artista, álbum, duración, portada y estado;
- los conteos `total`, `owned`, `inFlight`, `failed` y `missing`.

La lista MUST resolverse con el token de Spotify de quien hace el request, así que funciona con
playlists privadas y con "Me gusta".

#### Scenario: Playlist con estados mezclados
- **GIVEN** la playlist "Late Night Drive" tiene 20 canciones: 14 descargadas, 2 en curso, 2 que fallaron y 2 nunca pedidas
- **WHEN** Gonik pide `GET /api/collections/playlist/<id>`
- **THEN** recibe las 20 canciones en orden con su estado, y los conteos `owned: 14, inFlight: 2, failed: 2, missing: 2`

#### Scenario: Colección nunca descargada
- **GIVEN** una playlist que un amigo le pasó a Lu, de la que no se pidió nada
- **WHEN** Lu la abre
- **THEN** todas las canciones vuelven con estado `missing` y `owned: 0`

#### Scenario: "Me gusta" grande
- **GIVEN** Gonik tiene 1.200 canciones en "Me gusta"
- **WHEN** pide `GET /api/collections/liked/liked?limit=100`
- **THEN** recibe las primeras 100 canciones, los conteos de la colección entera y un cursor para seguir

### Requirement: Estado global por canción
El estado de una canción MUST derivarse por su Spotify track id, sin importar qué colección o qué
persona la pidió. Cuando las señales se contradicen (archivo descargado, progreso de descarga, actividad
del worker, pedido pendiente, rechazos anteriores), MUST aplicarse esta precedencia:
`owned` > en curso (`queued`, `searching`, `comparing`, `downloading`) > `failed` > `missing`.

#### Scenario: Canción descargada desde otra playlist
- **GIVEN** Lu descargó "Persiana Americana" desde "Asado del sábado"
- **WHEN** Gonik abre "Rock nacional", que también la tiene
- **THEN** la canción aparece como `owned` en la playlist de Gonik

#### Scenario: Un intento falló y otro está en curso
- **GIVEN** "Redbone" falló en una corrida anterior y hay un reintento buscando
- **WHEN** se pide la colección que la contiene
- **THEN** la canción aparece como `searching`, no como `failed`

### Requirement: Resumen del juicio en cada canción
Cada canción `owned` MUST incluir un resumen de cómo se eligió el archivo:

- `filename`, `username` (peer de Soulseek) y `format`;
- el veredicto del juez que decidió (`label`) y su `score`;
- `uncertain: true` cuando la aceptación fue dudosa (veredicto distinto de `exact`, o score bajo el umbral configurado).

Cada canción `failed` MUST incluir cuántos candidatos se revisaron y el veredicto más frecuente.
Los conteos de la colección MUST incluir `uncertain`.

#### Scenario: Canción aceptada con veredicto exacto
- **GIVEN** "Breathe Deeper" se descargó con veredicto `exact` y score 0.94
- **WHEN** se pide la colección
- **THEN** la canción trae `judging: { label: "exact", score: 0.94, filename, username, format, uncertain: false }`

#### Scenario: Aceptación dudosa
- **GIVEN** "Mil Horas" se descargó con veredicto `wrong_version` porque no había otro candidato
- **WHEN** se pide la colección
- **THEN** la canción trae `uncertain: true` y el conteo `uncertain` de la colección la incluye

### Requirement: Detalle del juicio por canción
`GET /api/tracks/by-spotify/{spotifyId}/judging` MUST devolver, para el último intento de esa canción:

- la consulta que se hizo a Soulseek;
- todos los candidatos, cada uno con archivo, peer, tamaño, score y veredictos de cada juez (incluido el `raw` del juez, para auditar);
- cuál se eligió, o por qué se rechazó la canción.

Cualquier persona con sesión MUST poder verlo.

#### Scenario: Ver por qué falló
- **GIVEN** "Redbone" falló con 4 candidatos rechazados
- **WHEN** Lu pide su detalle de juicio
- **THEN** recibe los 4 candidatos con sus veredictos (`wrong_version`, `wrong_artist`…) y el motivo del rechazo

#### Scenario: Ver por qué se eligió un archivo
- **GIVEN** "Breathe Deeper" está descargada
- **WHEN** Gonik pide su detalle de juicio
- **THEN** recibe el candidato elegido marcado `chosen: true` y los descartados con sus veredictos

### Requirement: Actualización en vivo
El endpoint de colección MUST aceptar `?since=<cursor>` y devolver solo las canciones cuyo estado
cambió, para que la UI pueda hacer polling cada 1,5 s sin volver a traer la lista de Spotify.

#### Scenario: Polling de una colección abierta
- **GIVEN** la UI tiene abierta una colección y el cursor de la última respuesta
- **WHEN** una canción pasa de `downloading` a `owned` y la UI pide con `since`
- **THEN** la respuesta incluye solo esa canción y los conteos actualizados
