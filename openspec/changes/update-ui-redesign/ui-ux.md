# UI/UX: update-ui-redesign

**Estado:** Aplica

**Justificación si "No aplica":** —

## Componentes y flujos

| Componente | Cambio | Estados |
|---|---|---|
| `LibraryRail` | Nuevo. Agregar · Buscar · chips Todo/Playlists/Álbumes · lista · Veredictos · Archivos · Sistema (admin) | cargando (skeleton de 6 filas) · vacía ("Tu biblioteca de Spotify está vacía") · `stale` (punto gris + "Sin conexión con Spotify") · panel deslizable en móvil |
| `AddFromSpotifyDialog` | Nuevo | vacío (instrucciones + nota) · link inválido · resolviendo (spinner en la vista previa) · vista previa · ya en la biblioteca · error de Spotify |
| `CollectionView` | Nuevo | cargando · lista · error de Spotify con "Reintentar" · pestaña vacía ("No hay canciones acá.") |
| `CollectionMenu` ("⋯") | Nuevo | Más intentos · Sumar canciones parecidas → vista previa → "Sumar N y descargar" · Abrir en Spotify · (Mantener sincronizada, detrás de flag) |
| `TrackList` / `StatusCell` | Reemplaza a `TrackTable` / `StatusBadge` | Descargada (veredicto + score, marca si dudosa) · Falta → Descargar · En cola · Buscando · Comparando · N% · Falló → Ver por qué · seleccionada |
| `JudgingPanel` | Reemplaza a `CandidateModal` | cargando · elegida (archivo elegido + descartados) · fallida (motivo + candidatos + Reintentar / Usar igual) · comparando (en vivo) · sin intentos ("Todavía no se buscó") |
| `VerdictsView` | Desde `JudgementsView` | feed · filtro por veredicto · vacío · selector de juez (admin) |
| `TransferBar` / `QueuePanel` | Nuevos | descargando · inactivo · en pausa (admin: Reanudar) · cola vacía |
| `FilesView` | Desde `DownloadsBrowser` | por carpeta · filtrado · vacío |
| `SystemView` | Reúne Manage, juez, registros y personas | tabs Personas / Workers / Juez / Registros |
| Menú de perfil | Idioma (ES/EN) · Cerrar sesión | — |

Flujos principales:

1. **Agregar y descargar:** "Agregar desde Spotify" → pegar link → vista previa → "Descargar las N" →
   la colección aparece en la biblioteca y se abre con las canciones en cola.
2. **Completar una playlist:** biblioteca → colección → "Descargar las N que faltan" → la barra de abajo
   muestra el progreso.
3. **Entender el juez:**
   - tocar una fila → `JudgingPanel` → archivo elegido y descartados, con el veredicto y el texto del juez;
   - en una que falló → "Buscar de nuevo con más intentos" o "Usar igual";
   - la pestaña "Dudosas" revisa las aceptaciones dudosas de una colección;
   - "Veredictos" muestra lo que el juez decide en general.

## Wireframes / mockups

Maqueta interactiva con datos de ejemplo:
https://claude.ai/artifact/QtmsGMSjGp6dS8Up6ygpUg

```
┌────────────────────┬──────────────────────────────────────────────────────────┐
│ convert/invert  (G)│  ┌────┐ Playlist                                         │
│ [+ Agregar desde   │  │    │ Late Night Drive                                 │
│    Spotify       ] │  └────┘ Gonik · 20 canciones · 1 h 32 min                │
│ [⌕ Buscar        ] │         ▬▬▬▬▬▬▬▬▬▬░░  Tenés 14 de 20 · 2 en curso         │
│ BIBLIOTECA  Todo…  │ [↓ Descargar las 4 que faltan] [.zip] ⋯   Todas Las tenés │
│ ▢ Tus me gusta 18/31│                                Faltan Fallaron Dudosas │
│ ▢ Late Night  14/20│ ─────────────────────────────────────────────────────────│
│ ▢ Kid A          ✓ │  1 ▪ Nightcall      Kavinsky   OutRun   4:18  ✓ Es esta·94│
│ ▢ Asado del sábado │  9 ▪ Let It Happen  Tame Impala Currents 7:47 ◔ 47%      │
│ ── Veredictos      │ 14 ▪ Redbone        C. Gambino  Awaken…  5:27 ✕ Falló    │
│ ── Archivos        │ 20 ▪ Adiós          G. Cerati   Fuerza…  3:19 • Falta    │
│ ── Sistema   admin │                                                          │
├────────────────────┴──────────────────────────────────────────────────────────┤
│ ▪ Let It Happen · Tame Impala ▬▬░   ↓ 2 descargando  ⌕ 4 buscando  ◷ 7   ‖ [Cola]│
└───────────────────────────────────────────────────────────────────────────────┘

Panel de juicio (al tocar una fila)                 ┌───────────────────────────┐
                                                    │ ▪ Breathe Deeper       ✕  │
                                                    │   Tame Impala · Slow Rush │
                                                    │ Consulta: "Breathe Deeper │
                                                    │  Tame Impala"             │
                                                    │ ELEGIDO                   │
                                                    │ 06 Breathe Deeper.flac    │
                                                    │ Es esta · 94 · tapes_ar · │
                                                    │ 41 MB · flac   ▸ jueces   │
                                                    │ DESCARTADOS (5)           │
                                                    │ … (Live).mp3 Otra versión │
                                                    └───────────────────────────┘
```

## Accesibilidad

| Aspecto | Decisión |
|---|---|
| Roles ARIA | Barra lateral `<nav aria-label="Biblioteca">`, ítem activo con `aria-current="page"`. `TrackList` como `role="grid"` con filas `role="row"`. `AddFromSpotifyDialog` y `JudgingPanel` con Radix `Dialog` (`aria-modal`, título asociado). Menús con Radix `DropdownMenu`. Pestañas con Radix `Tabs`. Avisos con `role="status"` (sonner). Progreso con `role="progressbar"` + `aria-valuenow` |
| Navegación por teclado | `/` enfoca el buscador. Flechas ↑/↓ recorren las filas, Enter abre el panel de juicio, Espacio selecciona, `d` descarga la fila. Escape cierra paneles y menús y devuelve el foco al disparador. Los botones de estado que cambian con hover ("Falta" → "Descargar") también cambian con foco |
| Foco visible | Anillo de 1,5px con el color de texto en todos los controles; nunca se quita sin reemplazo |
| Contraste | Texto y texto atenuado ≥ 4.5:1 sobre el fondo en ambos temas; el acento ámbar sobre fondo ≥ 3:1 para íconos y ≥ 4.5:1 para texto (se usa la variante oscura `#ad580b` en tema claro). El estado no depende solo del color: cada estado tiene ícono y texto |
| Lectores de pantalla | Cada fila anuncia título, artista y estado ("Descargada, es esta, 94"). Los cambios de estado de la colección abierta se anuncian de forma resumida (`aria-live="polite"` en la línea "Tenés X de N"), no por fila. `lang` del documento sigue al idioma elegido |
| Movimiento | Spinners y transiciones respetan `prefers-reduced-motion` |
