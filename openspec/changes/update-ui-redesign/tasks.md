# Tasks: update-ui-redesign

Ver design.md para el approach y ui-ux.md para estados y accesibilidad. Usa los contratos de
`add-spotify-login` y `add-playlist-status`; con `dataSource = mock` se puede avanzar antes.

## Base

- [x] Tokens nuevos en `index.css` / `tailwind.config.ts`, fuentes Archivo + IBM Plex Mono, temas claro y oscuro
- [x] `lib/i18n` (`es.ts` fuente, `en.ts: typeof es`, `useT`, `useFormat`), resolución de idioma y `PATCH /api/me { locale }`
- [x] `lib/data` con `api` y `mock` (datos de la maqueta) y hooks `useLibrary`, `useCollection`, `useQueue`, `useJudging`, `useVerdicts`, con polling según design.md
- [x] `useHashRoute` + rutas + redirección de hashes viejos

## Shell

- [x] `AppShell` + `LibraryRail` (estados de ui-ux.md, panel deslizable en móvil)
- [x] `TransferBar` + `QueuePanel` (quién pidió, pausa solo admin)
- [x] Menú de perfil (idioma, tema, cerrar sesión)

## Colección

- [x] `CollectionView`: encabezado, "Tenés X de N", acción principal, .zip, pestañas con conteos (incluida "Dudosas")
- [x] `TrackList` virtualizada + `StatusCell` con veredicto y score en "Descargada" y marca de dudosa
- [x] Selección de filas y barra de selección
- [x] `CollectionMenu` (Más intentos, Sumar canciones parecidas con vista previa, Abrir en Spotify; sincronizar detrás de flag)

## Juez

- [x] `JudgingPanel` desde `CandidateModal`: elegido / fallida / comparando en vivo / sin intentos; jueces y `raw` desplegables; `?track=` en el hash
- [x] Reintentar con más intentos y "Usar igual" (según el resultado del spike de `add-playlist-status`)
- [x] `VerdictsView` desde `JudgementsView`, en la navegación principal, selector de juez solo admin

## Agregar

- [x] `AddFromSpotifyDialog` (reusa `SpotifyPreview` y `lib/spotify.ts`) y pegado global de links

## Otras vistas

- [x] `SearchView` (canciones, álbumes, playlists); backend `GET /api/search` con el token de la persona
- [x] `FilesView` desde `DownloadsBrowser` (filtro, .zip por carpeta)
- [x] `SystemView`: Personas (invitar, rol, desactivar), Workers (desde `WorkersView`), Juez (`JudgeSwitch`), Registros

## Textos

- [x] Pasar todos los textos a `es.ts` / `en.ts` con el tono definido en el spec de `ui-i18n`; revisar con `/unslop` los textos en inglés
      (revisados a mano; `/unslop` no corrió en esta sesión)

## Limpieza

- [x] Borrar `StatCard`, `StatusBadge`, `Sidebar`, `PlaylistsView`, `TrackTable`, vistas inline de `App.tsx`, `lib/nav.ts`, Inter y JetBrains Mono

## Validation

- [x] `npx tsc --noEmit` sin errores (incluye el chequeo de claves de i18n)
- [x] `npm run build` ok
- [x] Test manual: los tres flujos de ui-ux.md, en español y en inglés, como admin y como miembro, en escritorio y a 400px
      (Playwright contra `?mock` y contra un backend descartable con sesiones sembradas; falta con Spotify real)
- [x] Regresiones: .zip, cancelar descarga, cambio de juez y pausa siguen andando
      (.zip, juez y pausa probados contra el backend; cancelar usa el mismo endpoint desde Sistema → Workers y no se probó con una descarga real en curso)
- [ ] a11y: recorrer biblioteca → colección → panel de juicio → diálogo de agregar solo con teclado; chequear contraste de los tokens en ambos temas; probar con un lector de pantalla las filas y la línea "Tenés X de N"
      (hecho: teclado en la lista ↑/↓/Enter/Espacio/d, Escape cierra paneles, `/` enfoca el buscador; contraste ≥ 4,5:1 en ambos temas
      después de pasar el texto "faint" a `muted`. Falta: lector de pantalla real)

## Post-archive

- [ ] `/documenter distill <dated-change-id>`: **auto-ejecutado por `/opsx:archive`**.
      Correr a mano solo si el auto-trigger falló (re-run con el id completo con fecha,
      ej. `2026-11-10-update-ui-redesign`). Sincroniza los use-cases `web-ui` y `ui-i18n`.
