# Proposal: Entrar con Spotify (usuarios, sesiones y roles)

**Change ID:** add-spotify-login
**Date:** 2026-10-15
**Author:** Eduardo Gonik

## Why

Hoy no hay usuarios. Todo `/api` se protege con un único `X-API-Key` que el frontend lleva compilado
en el bundle, así que en la práctica lo tiene cualquiera que abra la página. Además, la app solo habla
con Spotify por client credentials: no puede ver las playlists de nadie, ni las privadas, ni los
"Me gusta".

La app la usa un grupo chico de personas. Con "Entrar con Spotify" se resuelven las dos cosas a la vez:

- cada persona entra con una cuenta que ya tiene;
- el backend obtiene un token por usuario para leer *su* biblioteca;
- aparece la distinción admin/miembro que la UI nueva necesita para esconder las pantallas operativas.

## Scope

- **Capability `spotify-login`** (nueva): login OAuth con Spotify, lista de personas invitadas,
  sesiones por cookie, roles `admin`/`member`, logout. El `X-API-Key` queda como token de servicio para scripts.
- **Capability `spotify-library`** (nueva): endpoint que devuelve la biblioteca de Spotify de la persona
  (playlists propias y seguidas, "Tus me gusta", álbumes guardados) con metadata para la barra lateral.
- Pantalla de login mínima y manejo de sesión en el frontend (lo justo para no romper la app actual;
  el rediseño completo es `update-ui-redesign`).

**Comunidades afectadas:** ver context.md → Nodos afectados (`graph://node:require_api_key`,
`graph://node:AppConfig`, `graph://node:build_cors`, `graph://node:authHeaders`).

**Archivos principales:**
- `convert-invert/src/bin/trigger_server/{main.rs, middleware.rs, config.rs, state.rs}` + nuevo `auth.rs`
- `convert-invert/migrations/<nueva>` + `src/internals/database/schema.rs`
- `convert-invert-frontend/lib/api-client.ts`, `App.tsx` + nuevo `components/LoginScreen.tsx`
- `docker-compose.yml`

## Impact

- **Todos los endpoints de `/api`** pasan a exigir sesión (o token de servicio). El frontend deja de
  mandar `X-API-Key` y pasa a usar cookies (`credentials: "include"`).
- **Endpoints operativos** (workers, pausa, juez, registros, cancelar descargas) quedan solo para admins.
- **CORS** pasa a permitir credenciales para los orígenes configurados.
- **Deploy:** se agregan las env vars `SPOTIFY_REDIRECT_URI`, `TOKEN_ENC_KEY`, `ADMIN_EMAILS` y
  `COOKIE_SECURE`, y hay que rotar `API_KEY`.
- **Change que depende de este:** `add-playlist-status`, que usa el token de usuario para resolver
  colecciones privadas y "Me gusta".

## Non-goals

- Registro abierto: solo entran personas invitadas.
- Login con otro proveedor, o con usuario y contraseña.
- Escribir en Spotify (crear playlists, dar "Me gusta").
- El rediseño visual (`update-ui-redesign`) y el estado por playlist (`add-playlist-status`).
- Repartir la cola de forma justa entre usuarios.

## Conflictos con decisiones existentes

Ninguno: no existe `knowledge/decisions.md`. Este change **reemplaza** el modelo de auth por API key
compartido, que no estaba documentado como decisión.
