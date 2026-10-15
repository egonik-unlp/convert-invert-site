# Context: update-ui-redesign

> **Fuente del contexto.** El MCP de Graphify no conectó y no hay `graphify-out/`. Los nodos salen de
> leer `convert-invert-frontend/` (explore del 2026-10-15) y se citan por ancla de símbolo. Correr
> `/opsx:refresh-context update-ui-redesign` cuando exista el grafo. `knowledge/` no existe todavía.
>
> **Depende de** `add-spotify-login` (sesión, roles, biblioteca) y `add-playlist-status` (colecciones,
> pedidos, cola, juicio). Se puede empezar en paralelo contra datos mockeados.

## Nodos afectados

- `graph://node:Dashboard` (`App.tsx`, ~26 KB): todo el estado global, el polling y las vistas
  `OverviewView`, `LibraryView` y `LogsView` inline.
- `graph://node:NAV` (`lib/nav.ts`): 7 vistas que siguen la estructura interna del sistema
  (overview, library, judgements, playlists, downloads, diagnostics, logs).
- `graph://node:Sidebar`, `graph://node:StatCard`, `graph://node:TrackTable`, `graph://node:StatusBadge`.
- `graph://node:PlaylistsView`: formulario de corrida (link + workers / chunk / rango / retries / extend).
- `graph://node:DownloadsBrowser`: archivos en disco por carpeta, zip.
- `graph://node:CandidateModal`, `graph://node:JudgementsView`, `graph://node:JudgeSwitch`,
  `graph://node:JudgementBadge`, `graph://node:lib/judgement`: todo lo del juez.
- `graph://node:WorkersView` (Manage), `graph://node:SpotifyPreview` / `graph://node:useSpotifyPreview`.
- Tokens en `index.css` y `tailwind.config.ts`; fuentes Inter y JetBrains Mono.
- No hay i18n: todos los textos están inline en JSX, en inglés.

## Archivos relevantes

| Archivo | Rol |
|---|---|
| `convert-invert-frontend/App.tsx` | Shell, estado, polling, vistas inline |
| `convert-invert-frontend/lib/nav.ts` | Definición de vistas |
| `convert-invert-frontend/components/Sidebar.tsx` | Navegación actual |
| `convert-invert-frontend/components/PlaylistsView.tsx` | Formulario de corrida (se reemplaza) |
| `convert-invert-frontend/components/TrackTable.tsx` | Tabla virtualizada (base de la lista nueva) |
| `convert-invert-frontend/components/DownloadsBrowser.tsx` | Archivos (pasa a Archivos) |
| `convert-invert-frontend/components/CandidateModal.tsx` | Candidatos (pasa al panel de juicio) |
| `convert-invert-frontend/components/JudgementsView.tsx` | Feed de veredictos (pasa a Veredictos) |
| `convert-invert-frontend/components/JudgeSwitch.tsx` | Cambio de juez (admin) |
| `convert-invert-frontend/components/WorkersView.tsx` | Manage (pasa a Sistema) |
| `convert-invert-frontend/lib/judgement.ts` | Taxonomía y labels de veredictos |
| `convert-invert-frontend/lib/status.ts` | Metadata de estados |
| `convert-invert-frontend/index.css`, `tailwind.config.ts`, `index.html` | Tokens, fuentes, tema |
| `convert-invert-frontend/lib/api-client.ts` | Cliente (contratos de los otros dos changes) |

## Contexto knowledge

No hay `knowledge/`. Lo decidido en el explore y en la revisión de la maqueta:

- **Diagnóstico:** se nota que la hizo una IA (shadcn por defecto, tarjetas e íconos en todo, copy que
  se describe a sí misma). Además cuesta saber cómo hacer las cosas y el concepto "playlist" está
  partido en tres vistas.
- **Estructura:** como la de Spotify. Biblioteca a la izquierda, colección abierta a la derecha, barra
  de transferencias abajo. Se toma la estructura de Spotify, no su identidad (nada de verde Spotify).
- **Diseño mínimo:** el usuario pidió que los elementos sean más chicos. Texto base de 13px, filas de
  44px, sin tarjetas ni sombras, separación por líneas finas, un solo acento (ámbar) reservado a las
  acciones de descarga.
- **Agregar una playlist** tiene que ser obvio: un botón "Agregar desde Spotify" en la barra lateral,
  que abre un diálogo de pegar link con vista previa.
- **La info del juez tiene que estar a mano:** mostrar cómo se eligió cada canción y hacerla fácil de abrir.
- **Idiomas:** español con voseo y inglés. Los textos de Sistema también se traducen.
- **Roles:** los miembros no ven Sistema ni el botón de pausa.
- **Archivos** se mantiene como vista secundaria.
- Maqueta: https://claude.ai/artifact/QtmsGMSjGp6dS8Up6ygpUg

## Riesgos identificados

- Es casi una reescritura del frontend, así que hay riesgo de regresiones en flujos que hoy andan
  (zip, cancelar descargas, judge switch). Mitigación: migrar componente por componente y borrar las
  vistas viejas recién al final.
- Si `add-playlist-status` todavía no está, la UI queda bloqueada en datos reales. Mitigación: un
  adaptador de datos que hable con mocks durante el desarrollo.
- "Usar igual" depende del spike de `add-playlist-status`. Puede quedar escondido.
- "Mantener sincronizada" no tiene backend: se esconde detrás de un flag.
