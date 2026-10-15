# Tasks: add-spotify-login

Ver design.md para el approach técnico.

## Spike

- [ ] Registrar la app en el dashboard de Spotify con `SPOTIFY_REDIRECT_URI`, agregar 2 cuentas de prueba y confirmar el tope vigente de usuarios en development mode
- [ ] Con un token de usuario, confirmar qué devuelve `/v1/me/playlists` para playlists editoriales/algorítmicas de Spotify (riesgo de context.md)

## Backend

- [x] Migración `users` / `sessions` / `spotify_tokens` (up/down) y regenerar `schema.rs`
- [x] Config: `SPOTIFY_REDIRECT_URI`, `TOKEN_ENC_KEY` (falla al arrancar si falta o no tiene 32 bytes), `ADMIN_EMAILS`, `COOKIE_SECURE`
- [x] `auth.rs`: `GET /api/auth/login` (state + PKCE; pendiente en Redis, ver design.md), `GET /api/auth/callback`, `POST /api/auth/logout`, `GET /api/auth/me`
- [x] Lista de invitados: `GET/POST/PATCH /api/admin/users` (invitar por email, cambiar rol, desactivar → invalida sesiones)
- [x] `require_auth` reemplaza a `require_api_key` (cookie → sesión, si no `X-API-Key` como servicio); rutas públicas fuera del scope protegido
- [x] `RequireAdmin` en los handlers operativos listados en design.md
- [x] CSRF: chequeo de `Origin` (o `Sec-Fetch-Site`) en métodos que no son GET; CORS con credenciales
- [x] `spotify_user.rs`: cifrado AES-GCM, `access_token_for` con refresh + lock en Redis, manejo de `invalid_grant`
- [x] `GET /api/me/library` con caché de 5 min, `refresh=1` y fallback `stale`
- [x] `api::config` deja de anunciar `api_key` (`targetUrl` resultó ser solo del frontend: `/api/health` nunca lo expuso)
- [x] Tests: callback con state inválido, persona no invitada, sesión vencida, miembro → 403 en endpoint operativo, script con API key, refresh de token
      (unitarios + e2e contra Postgres/Redis descartables. El refresh contra Spotify real queda para el test manual: solo están testeados el cifrado y el manejo de `invalid_grant` por código)

## Frontend

- [x] `api-client.ts`: sacar `VITE_API_KEY`, `credentials: "include"`, evento `auth:required` ante 401
- [x] `AuthContext` + `GET /api/auth/me` al bootear
- [x] `LoginScreen` (estados default / `not_invited` / `spotify` / `state`) y menú de perfil con "Cerrar sesión"
      (el ítem "Idioma" del menú queda para `update-ui-redesign`, que trae el i18n de toda la app; el login ya tiene ES/EN)
- [x] Esconder Manage / Logs / Judgements a miembros
- [x] Preservar el hash de la vista a través del login

## Deploy

- [x] `docker-compose.yml` con las env vars nuevas; documentar qué pasa si se pierde `TOKEN_ENC_KEY` (`.env.example`)
- [ ] Rotar `API_KEY` en el deploy (estuvo en el bundle JS): acción manual

## Validation

- [x] `cargo test` y `cargo clippy` sin errores nuevos en `convert-invert`
- [x] `npx tsc --noEmit` sin errores en `convert-invert-frontend`
- [ ] Test manual: invitar a una cuenta, entrar, ver la biblioteca, cerrar sesión; una cuenta no invitada ve el mensaje de invitación
- [ ] a11y: recorrer login y menú de perfil solo con teclado; error de callback anunciado por lector de pantalla

## Post-archive

- [ ] `/documenter distill <dated-change-id>`: **auto-ejecutado por `/opsx:archive`**.
      Correr a mano solo si el auto-trigger falló (re-run con el id completo con fecha,
      ej. `2026-10-20-add-spotify-login`). Sincroniza los use-cases `spotify-login` y `spotify-library`
      (`knowledge/modules/<m>/use-cases/`) con lo que shippeó el change.
