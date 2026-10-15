# Context: add-spotify-login

> **Fuente del contexto.** El MCP de Graphify no conectó en esta sesión y el repo no tiene
> `graphify-out/` ni `GRAPH_REPORT.md`. Los nodos de abajo salen de leer el código directamente
> (sesión de `/opsx:explore` del 2026-10-15) y se citan por ancla de símbolo estable. Correr
> `/opsx:refresh-context add-spotify-login` cuando el grafo exista.
>
> `knowledge/` todavía no existe (falta `/documenter bootstrap`), así que no hay decisiones macro
> contra las que chequear.

## Nodos afectados

- `graph://node:require_api_key`: middleware que hoy protege todo `/api` con un `X-API-Key` compartido
  (`convert-invert/src/bin/trigger_server/middleware.rs`).
- `graph://node:AppState` / `graph://node:AppConfig`: estado del server y config; `api_key` vive en la config.
- `graph://node:build_cors`: CORS con `allowed_headers` = `X-API-Key`, `Content-Type`; sin credenciales.
- `graph://node:QueryManager::spotify_client_credentials`: única forma de hablar con Spotify hoy
  (client credentials, sin usuario).
- `graph://node:api::config`: expone `scheme: "api_key"` al frontend.
- `graph://node:authHeaders` / `graph://node:API_KEY` (frontend): el key se inyecta en el bundle vía `VITE_API_KEY`.
- `graph://node:Dashboard` (`App.tsx`): bootea con `getHealth` y no tiene noción de usuario.
- Migraciones Diesel (`convert-invert/migrations/`) + `graph://node:schema` (`src/internals/database/schema.rs`).

## Archivos relevantes

| Archivo | Rol |
|---|---|
| `convert-invert/src/bin/trigger_server/main.rs` | Arma el `App`, scopes, governors y el wrap de `require_api_key` |
| `convert-invert/src/bin/trigger_server/middleware.rs` | Validación del API key (a reemplazar/extender) |
| `convert-invert/src/bin/trigger_server/config.rs` | `api_key`, `allowed_origins`; acá entran las nuevas env vars |
| `convert-invert/src/bin/trigger_server/state.rs` | `AppState` (pools de DB y Redis) |
| `convert-invert/src/bin/trigger_server/api.rs` | Handlers; `config` anuncia el esquema de auth |
| `convert-invert/src/internals/query/query_manager.rs` | Cliente Spotify (client credentials) |
| `convert-invert/src/internals/database/schema.rs` | Schema Diesel generado |
| `convert-invert/migrations/` | Nueva migración `users` / `sessions` / `spotify_tokens` |
| `convert-invert-frontend/lib/api-client.ts` | `authHeaders`, `fetchWithTimeout`, `handleResponse` |
| `convert-invert-frontend/App.tsx` | Boot, layout, estado global |
| `docker-compose.yml` | Env vars del servicio `api` |
| `convert-invert-frontend/nginx.conf` | Proxy same-origin de `/api` (el callback OAuth pasa por acá) |

## Contexto knowledge

- No hay `knowledge/` ni decisiones registradas.
- Lo que se decidió en el explore (2026-10-15):
  - Los usuarios son un grupo chico: el dueño y algunas personas invitadas.
  - El login con Spotify es a la vez la identidad y la fuente de la biblioteca de cada persona.
  - Hay dos roles: `admin` (ve Sistema: workers, juez, registros, pausa) y `member` (solo su música).
  - La UI va en español (voseo) e inglés. Eso vive en el change `update-ui-redesign`.
- Maqueta de referencia: https://claude.ai/artifact/QtmsGMSjGp6dS8Up6ygpUg

## Riesgos identificados

- **Development mode de Spotify:** cada persona se agrega a mano en el dashboard de Spotify y hay un
  tope chico de usuarios. Alcanza para el grupo, pero hay que verificar el tope vigente antes de comprometerse.
- **Restricciones de la Web API desde fines de 2024:** apps nuevas podrían no leer playlists
  editoriales/algorítmicas de Spotify. Verificar con las credenciales reales.
- **Consumidores del `X-API-Key`:** el `analyze_run_log` y cualquier script externo que llame la API.
  Mantener el key como token de servicio evita romperlos.
- **El key actual está en el bundle JS.** Hoy cualquiera que cargue la página lo tiene. Este change
  corrige eso, pero el key hay que rotarlo al deployar.
- **Cookies en dev:** el server corre en HTTP local, así que `Secure` tiene que ser configurable.
