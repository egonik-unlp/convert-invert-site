# Delta Spec: update-ui-redesign

**Capability:** web-ui
**Change:** update-ui-redesign

## ADDED Requirements

### Requirement: Shell con biblioteca
La app MUST tener tres zonas:

- **una barra lateral** con un botón "Agregar desde Spotify", un buscador, la biblioteca de la persona y
  los accesos a Veredictos, Archivos y Sistema (este último solo para admin);
- **la colección abierta**;
- **una barra de transferencias abajo.**

Cada ítem de la biblioteca MUST mostrar portada, nombre, tipo y dueño, y un indicador de estado:
✓ si está completa, `x/y` con spinner si hay algo en curso, `x/y` si está parcial, nada si nunca se
descargó.

#### Scenario: Primera vista
- **GIVEN** Gonik entra con sesión
- **WHEN** carga la app
- **THEN** ve su biblioteca de Spotify en la barra lateral, "Tus me gusta" primero, y la última colección que tenía abierta

#### Scenario: Miembro
- **GIVEN** Lu tiene rol `member`
- **WHEN** carga la app
- **THEN** no ve el acceso a Sistema ni el botón de pausa de la barra de transferencias

### Requirement: Agregar desde Spotify
El botón "Agregar desde Spotify" MUST abrir un diálogo con un solo campo para pegar un link de
playlist, álbum o canción, con instrucciones de dónde copiarlo. Con un link válido, el diálogo MUST
mostrar una vista previa (portada, nombre, dueño, cantidad de canciones, cuántas ya tenés) y dos
acciones:

- "Ver canciones": agrega a la biblioteca y abre;
- "Descargar las N": agrega, encola y abre.

Pegar un link de Spotify en cualquier lugar de la app (o en el buscador) MUST abrir el mismo diálogo.

#### Scenario: Pegar un link que le pasaron
- **GIVEN** Lu tiene el link de una playlist de Martín
- **WHEN** toca "Agregar desde Spotify", lo pega y toca "Descargar las 12"
- **THEN** la playlist aparece en su biblioteca, se abre y sus canciones pasan a "En cola"

#### Scenario: Link inválido
- **GIVEN** el diálogo abierto
- **WHEN** Lu pega un texto que no es un link de Spotify
- **THEN** el diálogo muestra "Eso no parece un link de Spotify." y las instrucciones para copiar uno

### Requirement: Vista de colección
La vista de colección MUST mostrar:

- un encabezado con portada, tipo, nombre, dueño, cantidad de canciones y duración;
- una línea "Tenés X de N", con una barra de progreso segmentada (tenés / en curso / fallaron);
- la acción principal: "Descargar las N que faltan", "Descargar las N" si no hay nada, o deshabilitada
  con "Ya tenés todo" / "Bajando N…";
- el botón ".zip";
- un menú "⋯" con "Más intentos", "Sumar canciones parecidas" (con vista previa) y "Abrir en Spotify";
- las pestañas "Todas", "Las tenés", "Faltan", "Fallaron" y "Dudosas", cada una con su conteo
  ("Fallaron" y "Dudosas" solo si hay alguna).

#### Scenario: Descargar lo que falta
- **GIVEN** "Late Night Drive" con 14 de 20 descargadas, 2 en curso y 4 que faltan o fallaron
- **WHEN** Gonik toca "Descargar las 4 que faltan"
- **THEN** esas 4 pasan a "En cola", aparece un aviso "Sumamos 4 canciones a la cola" y el botón pasa a "Bajando 6…"

### Requirement: Fila de canción
Cada fila MUST mostrar número, portada, título, artista, álbum, duración y estado:

- "Descargada", con el veredicto del juez y el score (por ejemplo "Es esta · 94");
- "Falta", que con hover o foco se convierte en "Descargar";
- "En cola", "Buscando", "Comparando", o el porcentaje de descarga;
- "Falló", que con hover o foco se convierte en "Ver por qué".

Las canciones que faltan o fallaron MUST verse atenuadas. Las descargadas con aceptación dudosa MUST
llevar una marca visible. Con el mouse, cada fila MUST permitir seleccionar para descargar una selección.

#### Scenario: Descargar una sola canción
- **GIVEN** una fila en estado "Falta"
- **WHEN** Gonik toca "Descargar" en esa fila
- **THEN** solo esa canción pasa a "En cola"

#### Scenario: Selección
- **GIVEN** Lu marca 3 filas
- **WHEN** toca "Descargar" en la barra de selección
- **THEN** se encolan esas 3 y la selección se limpia

### Requirement: Panel de juicio
Tocar cualquier fila (o su estado) MUST abrir un panel lateral con el juicio de esa canción:

- la consulta que se hizo;
- el archivo elegido, con peer, tamaño, formato, veredicto y score, o el motivo del rechazo;
- los demás candidatos, con su veredicto y score;
- debajo de cada candidato, el veredicto de cada juez y el texto crudo del juez, desplegables.

Para una canción "Falló", MUST ofrecer "Buscar de nuevo con más intentos" y "Usar igual" en cada candidato.
Para una canción "Comparando", el panel MUST actualizarse en vivo a medida que llegan veredictos.

#### Scenario: Por qué falló
- **GIVEN** "Redbone" falló
- **WHEN** Lu toca "Ver por qué"
- **THEN** ve "No encontramos una versión que coincida", los 4 archivos revisados con veredictos como "Otra versión" u "Otro artista", y los botones para reintentar o usar uno igual

#### Scenario: Por qué se eligió este archivo
- **GIVEN** "Breathe Deeper" está descargada con "Es esta · 94"
- **WHEN** Gonik toca la fila
- **THEN** ve el archivo elegido arriba, marcado como elegido, y los candidatos descartados abajo con sus veredictos

### Requirement: Pestaña Dudosas
La pestaña "Dudosas" MUST listar las canciones descargadas cuya aceptación fue dudosa (veredicto
distinto de "Es esta" o score bajo el umbral), para revisarlas rápido desde el panel de juicio.

#### Scenario: Revisar aceptaciones dudosas
- **GIVEN** "Rock nacional" tiene 2 canciones aceptadas como "Otra versión"
- **WHEN** Gonik abre la pestaña "Dudosas"
- **THEN** ve esas 2 filas y puede abrir el panel de juicio de cada una

### Requirement: Veredictos
"Veredictos" MUST ser una entrada de la navegación principal, visible para todas las personas. Muestra
un feed de veredictos recientes (canción, archivo, veredicto, score, juez), filtrable por veredicto, y
un resumen de cuántos se aceptan y la demora promedio. Cada ítem MUST abrir el panel de juicio de esa
canción. El cambio de juez MUST quedar solo para admins.

#### Scenario: Miembro mira veredictos
- **GIVEN** Lu tiene rol `member`
- **WHEN** abre "Veredictos"
- **THEN** ve el feed y el resumen, pero no el selector de juez

### Requirement: Barra de transferencias y cola
La barra de abajo MUST mostrar:

- la canción que se está descargando, con su progreso (o "No hay nada descargándose");
- los conteos de descargando, buscando y en cola;
- un botón "Cola";
- el botón de pausa, solo para admin.

La cola MUST agrupar por estado y mostrar quién pidió cada canción ("vos" si fue la persona actual).
Con las descargas en pausa, la barra MUST decirlo y ofrecer "Reanudar" a los admins.

#### Scenario: Ver quién pidió
- **GIVEN** Martín pidió canciones de "Gym"
- **WHEN** Lu abre la cola
- **THEN** ve esas canciones con el avatar y el nombre de Martín

### Requirement: Archivos y Sistema
"Archivos" MUST listar los archivos descargados agrupados por carpeta, con filtro por nombre y ".zip"
por carpeta. "Sistema", solo para admin, MUST reunir:

- personas (invitar, cambiar rol, desactivar);
- workers;
- configuración del juez;
- registros.

#### Scenario: Admin invita a alguien
- **GIVEN** Gonik abre Sistema
- **WHEN** invita a `caro@example.com`
- **THEN** Caro aparece en la lista como invitada

### Requirement: Diseño mínimo
La UI MUST:

- usar texto base de 13px, filas de 44px y controles de 28 a 32px;
- separar con líneas finas, sin tarjetas ni sombras salvo en paneles flotantes;
- usar un único acento, reservado a las acciones de descarga y al progreso (verde y rojo solo para descargada y falló);
- tener tema claro y oscuro;
- funcionar a 400px de ancho, con la biblioteca como panel deslizable.

#### Scenario: Teléfono
- **GIVEN** la app abierta a 400px de ancho
- **WHEN** Lu abre una colección
- **THEN** ve título, artista y estado de cada canción sin scroll horizontal, y abre la biblioteca desde el botón de menú
