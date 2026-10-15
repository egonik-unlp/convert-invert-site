# Delta Spec: add-spotify-login

**Capability:** spotify-library
**Change:** add-spotify-login

## ADDED Requirements

### Requirement: Biblioteca de la persona
`GET /api/me/library` MUST devolver la biblioteca de Spotify de quien hace el request, en el orden de
Spotify:

- "Tus me gusta", primero y con id `liked`;
- las playlists propias y las seguidas;
- los álbumes guardados.

Cada ítem MUST incluir `kind` (`liked` | `playlist` | `album`), `id`, `name`, `owner`, `imageUrl` y
`trackCount`.

#### Scenario: Primera carga
- **GIVEN** Gonik tiene 6 playlists, 1 álbum guardado y canciones en "Me gusta"
- **WHEN** el frontend pide `GET /api/me/library`
- **THEN** recibe 8 ítems: primero `liked`, después las playlists y el álbum, con nombre, dueño, portada y cantidad de canciones

#### Scenario: Biblioteca de otra persona
- **GIVEN** Lu y Gonik tienen bibliotecas distintas
- **WHEN** cada una pide `GET /api/me/library`
- **THEN** cada una recibe solo su propia biblioteca

### Requirement: Caché de la biblioteca
El sistema MUST cachear la biblioteca por usuario durante 5 minutos, y MUST permitir forzar la recarga
con `?refresh=1`.

#### Scenario: Recarga forzada
- **GIVEN** Gonik creó una playlist en Spotify hace un minuto
- **WHEN** el frontend pide `GET /api/me/library?refresh=1`
- **THEN** la respuesta incluye la playlist nueva

### Requirement: Errores de Spotify
Si Spotify no responde o limita las llamadas (429), el sistema MUST devolver la última biblioteca
cacheada marcada como `stale: true`. Si no hay caché, MUST responder 502 con un mensaje que diga qué
pasó.

#### Scenario: Spotify con rate limit
- **GIVEN** hay una biblioteca cacheada de hace 20 minutos
- **WHEN** Spotify responde 429 al refrescar
- **THEN** el endpoint devuelve la biblioteca cacheada con `stale: true`
