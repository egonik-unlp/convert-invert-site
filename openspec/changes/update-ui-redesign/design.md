# Design: update-ui-redesign

## Approach

### Estructura

Se mantiene el stack: React 19, Vite, Tailwind 3, Radix (dialog, tooltip; se suman `dropdown-menu` y
`tabs`), `@tanstack/react-virtual`. Se parte `graph://node:Dashboard` en un shell y vistas por ruta:

```
App
├─ AuthProvider / I18nProvider / ThemeProvider
├─ LoginScreen                              (sin sesión; de add-spotify-login)
└─ AppShell
   ├─ LibraryRail      Agregar · Buscar · Biblioteca · Veredictos · Archivos · Sistema(admin)
   ├─ <Route>
   │   ├─ CollectionView   #/c/:kind/:id
   │   ├─ SearchView       (texto en el buscador)
   │   ├─ VerdictsView     #/verdicts         (antes JudgementsView)
   │   ├─ FilesView        #/files            (antes DownloadsBrowser)
   │   └─ SystemView       #/system/:tab      (Personas · Workers · Juez · Registros)
   ├─ TransferBar + QueuePanel
   ├─ JudgingPanel        (panel lateral, abierto por ?track=<spotifyId>; reemplaza CandidateModal)
   └─ AddFromSpotifyDialog
```

- **Router:** hash, para que siga andando detrás de nginx sin config extra. Sin librería: un hook
  `useHashRoute` de unas 40 líneas. Los hashes viejos (`#library`, `#playlists`…) redirigen a la
  última colección o a `#/`.
- **Datos:** un hook por recurso (`useLibrary`, `useCollection`, `useQueue`, `useJudging`,
  `useVerdicts`) sobre una capa `dataSource` con dos implementaciones, `api` y `mock`. El mock usa los
  mismos datos de la maqueta y permite avanzar antes de que `add-playlist-status` esté listo.
- **Polling:** cada 1,5 s solo se pollea lo visible.
  - `useCollection` con `since` (contrato de `add-playlist-status`).
  - `useQueue` para la barra.
  - `useJudging` solo mientras el panel está abierto y la canción está "Comparando".
  - Cuando la pestaña está oculta, se baja a 10 s (`document.visibilityState`).
  - La biblioteca se pollea cada 60 s.

### Información del juez

- **Fila:** el estado "Descargada" muestra la etiqueta corta del veredicto y el score, usando el
  resumen de `add-playlist-status`. Las etiquetas salen de `graph://node:lib/judgement` traducidas.
  `uncertain` agrega una marca (ícono de advertencia en el acento) y alimenta la pestaña "Dudosas".
- **`JudgingPanel`:** reemplaza a `graph://node:CandidateModal` y reusa su render de candidatos y
  `graph://node:JudgementBadge`.
  - Orden: arriba el elegido (o el motivo del rechazo), abajo los candidatos por score.
  - Cada candidato tiene un `<details>` con el veredicto por juez y el `raw`.
  - Se abre desde cualquier fila, desde la cola y desde Veredictos.
  - Usa `?track=` en el hash, así que se puede compartir el link.
- **`VerdictsView`:** es `graph://node:JudgementsView` con layout mínimo; el resumen arriba es una línea
  de texto, no stat cards. `graph://node:JudgeSwitch` se muestra solo a admins (y además está en Sistema → Juez).

### Diseño visual

- **Tokens:** se reescribe `index.css` con los valores de la maqueta.
  - Neutrales: fondo `#121214` / `#fafafa`, líneas `#262629` / `#e5e5e7`.
  - Acento ámbar `#e6a15c` / `#ad580b`. Verde y rojo semánticos.
  - Radios 5–8px, sin sombras salvo en flotantes.
  - Los tokens siguen expuestos a Tailwind como `hsl(var(--x) / <alpha>)`.
- **Tipografía:** Archivo (400/500/600) para la UI e IBM Plex Mono para nombres de archivo y
  registros, vía `@fontsource`. Se quitan Inter y JetBrains Mono. Escala: 11 / 12 / 13 / 15 / 24px.
- **Lista de canciones:** `graph://node:TrackTable` se reescribe como `TrackList`, virtualizada, con
  filas de 44px y grilla `24px 28px 1.4fr 1fr 44px 112px`. A menos de 640px queda en 4 columnas.
- **Eliminados:** `StatCard`, `StatusBadge` (reemplazado por `StatusCell`), `OverviewView`, `LibraryView`,
  `PlaylistsView` (su lógica de extensión pasa al menú "⋯"), `Sidebar` actual, el pill "Live" y los
  subtítulos de cada header.

### i18n

- `lib/i18n/es.ts` es la fuente; `en.ts` se tipa como `typeof es`, así que una clave faltante rompe
  `tsc` (scenario de clave faltante).
- Los valores son strings, o funciones para plurales e interpolación:
  `songs: (n) => n === 1 ? "1 canción" : \`${n} canciones\``.
- `useT()` devuelve el diccionario activo. `useFormat()` envuelve `Intl.NumberFormat` /
  `Intl.DateTimeFormat` / `Intl.RelativeTimeFormat` para el idioma.
- Resolución del idioma, en orden: `users.locale` (vía `/api/auth/me`), `localStorage` (login sin
  sesión) y `navigator.language`. El cambio se guarda con `PATCH /api/me { locale }` y actualiza `<html lang>`.
- Los textos de la maqueta son la base del diccionario en español; ya están escritos con voseo y en el tono pedido.

### Decisiones tomadas al implementar

- **"Agregar a la biblioteca" vive en el navegador.** Los scopes de Spotify son de solo lectura, así que la
  app no puede seguir una playlist en Spotify. "Ver canciones" y "Descargar las N" guardan la colección en
  `localStorage` (`ci-added`) y la barra lateral la muestra después de "Tus me gusta", marcada "agregada".
  No viaja entre dispositivos.
- **Indicador de la biblioteca sin llamar a Spotify.** `POST /api/collections/status` recibe los ítems de la
  barra y devuelve `{total, owned, inFlight, failed}` solo para las colecciones cuya lista de canciones el
  servidor ya leyó (al abrirlas o pedirlas: `collids:{kind}:{id}` en Redis, 30 días). Las nunca abiertas no
  muestran nada, que coincide con "nunca se descargó". Pollea cada 4 s si hay algo en curso, si no cada 30 s.
- **Búsqueda.** `GET /api/search?q=` usa el token de la persona (canciones, álbumes y playlists, 10 de cada uno,
  caché de 10 min) y devuelve las canciones con su estado, así el resultado muestra qué ya está descargado.
- **`.zip` de la colección = su carpeta.** La respuesta de colección trae `folder` (misma regla que
  `POST /requests`: nombre saneado, o `Liked Songs - {nombre}`) y `folderExists`. Si la carpeta no existe el
  botón queda deshabilitado. (Reemplazado por el espejado, más abajo.)
- **Espejado entre colecciones.** Una canción ya descargada bajo otra colección (de otra persona, otro
  álbum) se enlaza con hard link en la carpeta de cada colección que la contiene (symlink relativo si no
  se puede): no ocupa espacio y el .zip, el explorador y Soulseek la ven como archivo normal.
  `downloaded_file.local_path` guarda dónde quedó cada archivo; las filas viejas se completan buscando el
  nombre remoto en el árbol, solo si es único. Se espeja al pedir la colección (aunque no falte nada), al
  abrirla o pollearla si su carpeta ya existe, y antes de bajar su .zip (`POST
  /collections/{kind}/{id}/folder`). Así el .zip queda completo y el botón se habilita apenas hay algo
  descargado, aunque la carpeta todavía no exista.
- **"Descargadas" reemplaza a Archivos.** Todo lo que está en disco, para cualquiera, sin depender de poder
  abrir la playlist de origen en Spotify (la de otra persona puede ser privada). Pestaña Canciones: lista con
  tapa, artista, álbum, formato y tamaño, quién la pidió y cuándo llegó, búsqueda por palabras y orden
  (recientes, artista, álbum, título), y bajar cada archivo (`GET /tracks/by-spotify/{id}/file`). Pestaña
  Colecciones: tarjetas con mosaico de tapas por playlist/álbum, armadas con la colección de origen de cada
  canción, los pedidos y las listas de canciones que el servidor ya leyó (así una canción aparece en cada
  colección que la tiene); cada una abre su lista con su .zip. Tapas y duraciones salen de lo que el servidor
  ya vio en Spotify (`trackmeta:*`), y solo se piden a Spotify, de a poco, las que nunca vio. El explorador de
  carpetas queda en Sistema → Archivos para admins. Las filas de cualquier colección y el panel de juicio
  también tienen "Bajar archivo".
- **Reproductor.** Las canciones descargadas se escuchan en la app: botón de play sobre la tapa (en
  Descargadas y en las filas de cualquier colección) y en el panel de la canción. La cola es lo descargado de
  la lista en pantalla desde la canción elegida. Una barra abajo (tapa, título, anterior/pausa/siguiente,
  posición, volumen) y Media Session para la pantalla bloqueada y las teclas multimedia. Usa el mismo
  `GET /tracks/by-spotify/{id}/file` con `?inline=1` (con rangos, así se puede adelantar). El contexto del
  tiempo está separado para que su actualización no re-renderice las filas.
- **Veredictos abren el panel.** El feed de `/api/judgements` suma `spotifyId` (de `search_items.track_id`).
- **"Usar igual" muestra quién.** El juicio manual guarda `{"acceptedBy", "by"}` en `raw`; el panel muestra
  "Elegido a mano por {by}".
- **Cola sin cancelar.** `/api/queue` no trae el id de la descarga, así que cancelar sigue en Sistema → Workers
  (descargas activas), igual que antes.
- **Mock.** `?mock` en la URL (o `VITE_MOCK=1`) corre la UI con datos de ejemplo que avanzan con el reloj
  (en cola → buscando → comparando → descargando → descargada). El menú de perfil suma "Mock: Lu (member)"
  para ver la vista de miembro. Todo pasa por `lib/data`; nada de la UI llama a `api` directo.
- **Tema.** Sigue al sistema hasta que la persona elige uno en el menú de perfil; recién ahí se guarda.
- **Contraste.** El gris "faint" (2,4:1 en claro) quedó solo para placeholders y puntos decorativos; todo texto
  usa `muted` (≥ 5,3:1 en ambos temas).
- **Dev proxy.** `vite.config.ts` lee `API_PROXY_TARGET` para apuntar el dev server a otro backend. El proxy
  cambia el `Host`, así que el origen del dev server tiene que estar en `ALLOWED_ORIGINS` para que pasen las
  escrituras (chequeo CSRF).

### Decisiones al armar las imágenes de Docker

- **Prefijo de ruta.** El bundle usa URLs relativas (`base: './'`, `API_BASE = "api"`), así que la misma
  imagen anda en `/` y montada bajo un prefijo (`/convert/` detrás de Caddy o Funnel). El backend saca el
  prefijo de `SPOTIFY_REDIRECT_URI` (`app_base`) para el redirect después del login y el `Path` de las
  cookies; no hace falta otra variable.
- **Spotify y http.** Spotify solo acepta redirect URIs http en una IP de loopback (`127.0.0.1`, no
  `localhost`). Entrar desde otra máquina necesita https; por eso existe el prefijo.
- **nginx del frontend.** Reenvía `Host $http_host` (con puerto): con `$host` el chequeo de mismo origen
  rechazaba toda escritura en `http://<ip>:5173`. Toma la IP real de `X-Forwarded-For` cuando el par es
  privado, y la pasa en `X-Real-IP`.
- **Rate limit por cliente.** `ClientIpKeyExtractor` usa `X-Real-IP` si el par es privado o loopback; si no,
  detrás de nginx todo el grupo compartía un balde de 4 req/s y una pestaña ya consume ~1,6.
- **Build de Rust con caché.** Registro y `target` en cache mounts; antes de compilar se tocan `src/` y
  `migrations/` porque Cargo decide por mtime y un `target` cacheado puede parecer más nuevo que el código
  copiado (pasó: la imagen salió con el binario viejo).

## Archivos a modificar

| Archivo | Cambio |
|---|---|
| `convert-invert-frontend/App.tsx` | Reducido a providers + `AppShell` |
| `convert-invert-frontend/lib/nav.ts` | Reemplazado por rutas (`lib/routes.ts`) |
| `convert-invert-frontend/lib/i18n/{es,en,index}.ts` (nuevo) | Diccionarios, `useT`, `useFormat` |
| `convert-invert-frontend/lib/data/{api,mock,index}.ts` (nuevo) | Capa `dataSource` |
| `convert-invert-frontend/components/shell/{AppShell,LibraryRail,TransferBar,QueuePanel}.tsx` (nuevo) | Shell |
| `convert-invert-frontend/components/collection/{CollectionView,TrackList,StatusCell,CollectionMenu}.tsx` (nuevo) | Vista de colección |
| `convert-invert-frontend/components/JudgingPanel.tsx` (nuevo, desde `CandidateModal.tsx`) | Panel de juicio |
| `convert-invert-frontend/components/AddFromSpotifyDialog.tsx` (nuevo; reusa `SpotifyPreview`, `lib/spotify.ts`) | Agregar desde Spotify |
| `convert-invert-frontend/components/VerdictsView.tsx` (desde `JudgementsView.tsx`) | Veredictos |
| `convert-invert-frontend/components/FilesView.tsx` (desde `DownloadsBrowser.tsx`) | Archivos |
| `convert-invert-frontend/components/SystemView.tsx` (reúne `WorkersView`, `JudgeSwitch`, logs, personas) | Sistema |
| `convert-invert-frontend/components/{StatCard,StatusBadge,Sidebar,PlaylistsView,TrackTable}.tsx` | Se borran al final |
| `convert-invert-frontend/index.css`, `tailwind.config.ts`, `index.html`, `package.json` | Tokens, fuentes |
| `convert-invert/src/bin/trigger_server/auth.rs` | `PATCH /api/me { locale }` |
| `convert-invert/src/bin/trigger_server/collections.rs` | `GET /api/search`, `POST /api/collections/status`, `folder` en la colección |
| `convert-invert/src/bin/trigger_server/api.rs` | `spotifyId` en el feed de veredictos |
| `convert-invert/src/bin/trigger_server/requests.rs` | Nombre de quien eligió en el juicio manual |

## Alternativas consideradas

- **Retocar el diseño actual** (colores y espaciado). Descartado: el problema es de estructura, no de skin.
- **`react-i18next`.** Descartado: son dos idiomas y unos pocos cientos de strings. Un diccionario tipado
  da chequeo de claves faltantes en compilación sin una dependencia más.
- **React Router.** Descartado por ahora: cinco rutas con hash no lo justifican.
- **Copiar la identidad de Spotify** (verde, Circular). Descartado: se toma la estructura, no la marca.
- **Dejar la info del juez solo en Sistema.** Descartado por pedido explícito: tiene que estar a mano en
  cada canción.

## Riesgos

- Regresiones en flujos existentes (zip, cancelar, judge switch). Migrarlos primero a sus vistas nuevas
  y probarlos antes de borrar los componentes viejos.
- La virtualización con filas que cambian de estado cada 1,5 s: mantener las keys estables por Spotify id
  y no re-renderizar la lista entera (memo por fila).
- Si "Usar igual" no sale del spike de `add-playlist-status`, se esconde el botón: queda solo el
  reintento con más intentos.
