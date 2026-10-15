# Delta Spec: update-ui-redesign

**Capability:** ui-i18n
**Change:** update-ui-redesign

## ADDED Requirements

### Requirement: Español e inglés
Todos los textos de la UI MUST estar disponibles en español rioplatense (voseo) y en inglés, incluidas
las pantallas de Sistema y Veredictos. MUST NOT quedar textos sin traducir en ninguna de las dos.

#### Scenario: Cambio de idioma
- **GIVEN** la app en español
- **WHEN** Gonik elige "English" en el menú de perfil
- **THEN** todos los textos visibles pasan a inglés sin recargar la página

#### Scenario: Clave faltante
- **GIVEN** un texto nuevo agregado solo al diccionario en español
- **WHEN** se corre el chequeo de tipos del frontend
- **THEN** el chequeo falla señalando la clave que falta en inglés

### Requirement: Idioma inicial y preferencia
La primera vez, el idioma MUST salir del navegador (`es-*` → español; cualquier otro → inglés).
La elección de la persona MUST guardarse en su usuario y MUST aplicarse en cualquier dispositivo donde
entre. La pantalla de login, sin sesión, MUST recordar la elección en el navegador.

#### Scenario: Otro dispositivo
- **GIVEN** Lu eligió inglés en la compu
- **WHEN** entra desde el teléfono, con el navegador en español
- **THEN** la app se muestra en inglés

### Requirement: Plurales, números y fechas
Los textos con cantidades MUST tener singular y plural ("1 canción" / "12 canciones",
"Descargar la que falta" / "Descargar las 4 que faltan"). Los números, tamaños y duraciones MUST
formatearse según el idioma (`Intl`).

#### Scenario: Tamaño en español
- **GIVEN** una carpeta de 1.5 GB
- **WHEN** la app está en español
- **THEN** se muestra "1,5 GB"

### Requirement: Tono de los textos
Los textos MUST ser cortos y directos, y nombrar las cosas como las reconoce quien usa la app (canciones,
playlists, cola), no como están hechas por dentro. Los botones MUST decir lo que hacen ("Descargar las 4
que faltan"). Los errores MUST decir qué pasó y qué hacer.

#### Scenario: Error de Spotify
- **GIVEN** Spotify no responde al abrir una colección
- **WHEN** la vista no puede cargar la lista
- **THEN** muestra "No pudimos leer esta playlist de Spotify. Probá de nuevo en un rato." con un botón "Reintentar"
