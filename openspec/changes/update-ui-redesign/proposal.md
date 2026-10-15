# Proposal: Rediseño de la UI (biblioteca al estilo Spotify, mínima, ES/EN)

**Change ID:** update-ui-redesign
**Date:** 2026-10-15
**Author:** Eduardo Gonik

## Why

- **Se nota que la hizo una IA:** es el look de shadcn por defecto, con una grilla de stat cards,
  íconos en cada label y subtítulos que explican cada pantalla.
- **Cuesta saber cómo hacer las cosas:** el menú sigue la estructura interna del sistema (7 vistas), y
  la playlist está partida en tres lugares (Playlists es un formulario, Library es un `<select>`,
  Downloads son carpetas).
- **Descargar se siente como configurar un job.**
- **No se puede ver de un vistazo qué tenés de una playlist.**
- **La información del juez,** que explica por qué se eligió o se rechazó una canción, está en un modal
  o en una pantalla aparte.
- **Solo está en inglés,** y el grupo que la usa habla español.

## Scope

- **Capability `web-ui`** (nueva):
  - shell con biblioteca, colección abierta y barra de transferencias;
  - "Agregar desde Spotify";
  - vista de colección con estado por canción y "Descargar las N que faltan";
  - información del juez en cada canción, y un panel de juicio que se abre desde cualquier fila;
  - pestaña "Dudosas";
  - "Veredictos" en la navegación principal;
  - cola compartida;
  - Archivos;
  - Sistema (solo admin);
  - diseño mínimo.
- **Capability `ui-i18n`** (nueva): español (voseo) e inglés, detección y preferencia guardada por usuario.

**Comunidades afectadas:** ver context.md → Nodos afectados (`graph://node:Dashboard`, `graph://node:NAV`,
`graph://node:PlaylistsView`, `graph://node:CandidateModal`, `graph://node:JudgementsView`).

**Archivos principales:** `App.tsx`, `lib/nav.ts`, `components/*`, `index.css`, `tailwind.config.ts`,
`index.html`, nuevo `lib/i18n/`.

## Impact

- Se reemplazan **Overview**, **Library**, **Playlists** y **Logs** (como vistas de primer nivel).
- **Judgements** pasa a "Veredictos" (visible para todos). **Manage** y **Logs** pasan a Sistema.
- **Fuentes:** Archivo + IBM Plex Mono reemplazan a Inter + JetBrains Mono.
- **Rutas:** cambia la deep-link por hash (`#/c/playlist/<id>`, `#/files`, `#/verdicts`, `#/system`).
  Los hashes viejos redirigen.
- **Usuario:** suma `PATCH /api/me` para guardar el idioma (columna `users.locale` de `add-spotify-login`).

## Non-goals

- Reproducir música en el navegador.
- Backend de "Mantener sincronizada" (la opción queda escondida tras un flag).
- Más idiomas que español e inglés.
- App móvil nativa. La web tiene que andar bien en el teléfono, pero no se hace una app aparte.

## Conflictos con decisiones existentes

Ninguno registrado. Este change revierte de hecho el diseño "Relay console" que describe `index.css`
(paleta slate + azure, tarjetas). No estaba registrado como decisión.
