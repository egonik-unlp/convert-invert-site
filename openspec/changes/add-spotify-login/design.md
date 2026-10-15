# Design: add-spotify-login

## Approach

### Flujo OAuth (server-side, Authorization Code + PKCE)

```
browser                      api (/api/auth/*)                         Spotify
  │ GET /api/auth/login ──────▶ genera state + code_verifier
  │                            guarda ambos en cookie firmada `ci_oauth` (10 min)
  │ ◀── 302 accounts.spotify.com/authorize?…&code_challenge=S256(verifier)&state
  │ ───────────────────────────────────────────────────────────────────▶ autoriza
  │ GET /api/auth/callback?code&state ◀──────────────────────────────── 302
  │                            verifica state, intercambia code (+verifier, +client_secret)
  │                            GET /v1/me → id, email, display_name, avatar
  │                            ¿invitado o en ADMIN_EMAILS? → upsert user, crea sesión
  │ ◀── 302 / + Set-Cookie ci_session
```

- El backend ya tiene `CLIENT_ID`/`CLIENT_SECRET` (`graph://node:QueryManager::spotify_client_credentials`).
  El intercambio se hace del lado del server, así que el secret nunca llega al navegador. PKCE se suma
  igual como defensa extra.
- Scopes: `user-read-email user-read-private playlist-read-private playlist-read-collaborative user-library-read`.
- El callback pasa por el proxy same-origin de nginx (`/api/*`), así que no hace falta una ruta nueva
  en `nginx.conf`. El valor de `SPOTIFY_REDIRECT_URI` tiene que estar registrado en el dashboard de Spotify.

### Modelo de datos (migración nueva)

| Tabla | Columnas |
|---|---|
| `users` | `id`, `spotify_id` (unique, nullable hasta el primer login), `email` (unique), `display_name`, `avatar_url`, `role` (`admin`/`member`), `status` (`invited`/`active`/`disabled`), `locale` (nullable), `created_at`, `last_seen_at` |
| `sessions` | `id`, `user_id`, `token_hash` (sha256, unique), `created_at`, `last_used_at`, `expires_at`, `user_agent` |
| `spotify_tokens` | `user_id` (pk), `refresh_token_enc` (bytea, AES-256-GCM, nonce prefijado), `access_token` (nullable), `access_expires_at`, `scopes` |

- La invitación es una fila en `users` con `status = invited` y solo el email. En el primer login se
  matchea por email y se completa `spotify_id`.
- Los admins de `ADMIN_EMAILS` se crean (o promueven) en el callback.

### Middleware

`graph://node:require_api_key` se reemplaza por `require_auth`, que resuelve un `Principal` y lo deja
en las extensions del request:

1. Si hay cookie `ci_session` → hash → busca sesión vigente y usuario activo → `Principal::User { id, role }`.
   Si `last_used_at` tiene más de 1 h, actualiza `last_used_at` y `expires_at`, para no escribir en cada request.
2. Si no, y hay `X-API-Key` válido (comparación en tiempo constante, como hoy) → `Principal::Service` (admin).
3. Si no hay ninguno → 401.

Hay un extractor `RequireAdmin` para los handlers operativos: `workers::stop_workers`,
`workers::worker_status`, `api::pipeline_pause`/`pipeline_resume`, `api::judge_switch`/`judge_reset`,
`api::logs` y `api::cancel_download`.

`/workers/start` sigue abierto a miembros hasta que `add-playlist-status` lo reemplace por pedidos de descarga.

Rutas públicas fuera del middleware: `/api/auth/login`, `/api/auth/callback` y `/api/health`.
`/api/health` deja de exponer `targetUrl`.

### CSRF y CORS

- `SameSite=Lax` alcanza para GET. En métodos que no son GET, el middleware exige `Content-Type: application/json`
  y un `Origin` dentro de `allowed_origins`.
- `graph://node:build_cors` pasa a `supports_credentials()` y saca `X-API-Key` de los headers permitidos
  para el browser. Los scripts no usan CORS.

### Tokens de Spotify

- Un módulo `spotify_user` expone `access_token_for(user_id)`:
  1. Lee el access token de la DB.
  2. Si vence en menos de 60 s, lo renueva con el refresh token descifrado y persiste el resultado.
     Spotify puede rotar el refresh token, así que también se guarda el nuevo.
  3. Hay un lock por usuario en Redis para que dos requests no renueven a la vez.
- Si la renovación falla con `invalid_grant` → se borran sus sesiones y sus tokens (scenario de token revocado).
- Cifrado con el crate `aes-gcm`. `TOKEN_ENC_KEY` son 32 bytes en base64. Sin la clave el server no arranca.

### Biblioteca (`GET /api/me/library`)

- Llama a `/v1/me/playlists`, `/v1/me/albums` y `/v1/me/tracks?limit=1` (para el total de "Me gusta")
  con el token del usuario, paginando.
- Caché en Redis `library:{user_id}`, TTL 5 min. Con `refresh=1` se ignora.
- Ante un 429 o un 5xx se sirve la última copia guardada (`library:{user_id}:last`, sin TTL) con `stale: true`.

### Frontend (mínimo, sin rediseño)

- `graph://node:authHeaders`: se elimina `VITE_API_KEY` y los fetch pasan a `credentials: "include"`.
- `handleResponse` emite un evento `auth:required` ante un 401. `App` muestra `LoginScreen`, que es un
  link a `/api/auth/login`.
- `GET /api/auth/me` al bootear → `{ id, name, avatarUrl, role, locale }`, expuesto en un `AuthContext`.
- La UI actual esconde Manage, Logs y Judgements a los miembros. El rediseño las reubica.

### Decisiones tomadas al implementar

- **Estado OAuth en Redis, no en cookie firmada.** `oauth:{state}` guarda `{ verifier, return_to }` con TTL de
  10 min y se consume con `GETDEL`. La cookie `ci_oauth` (HttpOnly, path `/api/auth`) solo lleva el `state`, para
  atar el callback al navegador que inició el login. Ahorra una clave de firma más.
- **El access token también se guarda cifrado** (`access_token_enc`), no solo el refresh token.
- **CSRF por `Origin`, sin exigir `Content-Type`.** Varios POST existentes (pausa, reset del juez) no tienen
  body. Se acepta si `Origin` está en `ALLOWED_ORIGINS` o coincide con el `Host` (o `X-Forwarded-Host`). Sin
  `Origin`, se acepta solo con `Sec-Fetch-Site: same-origin|none`. Ojo: detrás de nginx `$host` no lleva puerto,
  así que el origen público tiene que estar en `ALLOWED_ORIGINS`.
- **`/api/auth/logout` es pública,** para poder borrar la cookie aunque la sesión ya haya vencido.
- **Política de login como función pura** (`decide_login`): invitado o activo entra; email admin entra y se
  promueve; desactivado nunca entra.
- **Sin tokens de Spotify (`NotLinked`), `/api/me/library` responde 401,** igual que un token revocado.
- **El ítem "Idioma" del menú de perfil se difiere a `update-ui-redesign`.** El resto de la app sigue en inglés
  hasta entonces; la pantalla de login ya tiene ES/EN.

## Archivos a modificar

| Archivo | Cambio |
|---|---|
| `convert-invert/migrations/2026-10-xx_add_users_sessions/` | Nueva migración (up/down) |
| `convert-invert/src/internals/database/schema.rs` | Regenerar |
| `convert-invert/src/bin/trigger_server/auth.rs` (nuevo) | Handlers `login`, `callback`, `logout`, `me`, `invites`; `Principal`, `RequireAdmin` |
| `convert-invert/src/bin/trigger_server/spotify_user.rs` (nuevo) | Tokens por usuario, refresh, biblioteca |
| `convert-invert/src/bin/trigger_server/middleware.rs` | `require_api_key` → `require_auth` |
| `convert-invert/src/bin/trigger_server/main.rs` | Rutas públicas vs protegidas, CORS con credenciales |
| `convert-invert/src/bin/trigger_server/config.rs` | `SPOTIFY_REDIRECT_URI`, `TOKEN_ENC_KEY`, `ADMIN_EMAILS`, `COOKIE_SECURE` |
| `convert-invert/src/bin/trigger_server/api.rs` | `config` deja de anunciar `api_key`; handlers operativos con `RequireAdmin` |
| `convert-invert/src/bin/trigger_server/workers.rs` | `RequireAdmin` en stop/status |
| `convert-invert/Cargo.toml` | `aes-gcm`, `sha2`, `rand`, `base64` (si faltan) |
| `convert-invert-frontend/lib/api-client.ts` | Cookies, sin API key, evento 401 |
| `convert-invert-frontend/App.tsx` | `AuthContext`, login gate, ocultar vistas de admin |
| `convert-invert-frontend/components/LoginScreen.tsx` (nuevo) | Pantalla de login |
| `docker-compose.yml` | Env vars nuevas |

## Alternativas consideradas

- **JWT en vez de sesiones en DB.** Descartado: el grupo es chico, revocar (desactivar a alguien,
  token revocado) es un requisito, y una sesión opaca en DB lo resuelve sin listas negras.
- **PKCE puro en el navegador.** Descartado: el frontend tendría que guardar tokens de Spotify, y el
  backend igual los necesita para resolver playlists privadas al pedir una descarga.
- **Seguir con `X-API-Key` y agregar usuarios aparte.** Descartado: no da la biblioteca de cada persona
  y deja el key en el bundle.
- **Invitar por Spotify id en vez de email.** Descartado: nadie conoce su Spotify id; el email sí.

## Riesgos

- El tope de usuarios del development mode de Spotify. Si el grupo crece, hay que pedir extended quota.
- Si se pierde `TOKEN_ENC_KEY`, todos tienen que volver a entrar. No hay pérdida de datos, pero hay que documentarlo.
- Las cookies `Secure` en dev local sobre HTTP requieren `COOKIE_SECURE=false`, y es fácil olvidarlo en prod.
  Loguear un warning si el server arranca con `false` y `allowed_origins` no es localhost.
