# Delta Spec: add-playlist-status

**Capability:** download-requests
**Change:** add-playlist-status

## ADDED Requirements

### Requirement: Pedir lo que falta de una colección
`POST /api/requests` con `{ source: { kind, id }, trackIds?, options? }` MUST:

- resolver la colección con el token de quien pide;
- descartar las canciones que ya están `owned` o en curso;
- encolar el resto y devolver cuántas se encolaron.

Si viene `trackIds`, MUST considerar solo esas canciones.

#### Scenario: Descargar las que faltan
- **GIVEN** "Late Night Drive" tiene 2 canciones `missing` y 2 `failed`
- **WHEN** Gonik pide `POST /api/requests` con esa playlist
- **THEN** se encolan esas 4 canciones a su nombre y la respuesta dice `queued: 4`

#### Scenario: Nada para pedir
- **GIVEN** todas las canciones de "Kid A" están `owned`
- **WHEN** alguien pide la colección
- **THEN** la respuesta dice `queued: 0` y no se arranca ninguna corrida

#### Scenario: Selección
- **GIVEN** Lu selecciona 3 canciones de una playlist
- **WHEN** pide con `trackIds` de esas 3
- **THEN** se encolan solo esas 3

#### Scenario: "Me gusta" privado
- **GIVEN** los "Me gusta" de Lu solo los puede leer su token
- **WHEN** Lu pide `source: { kind: "liked", id: "liked" }`
- **THEN** el backend los resuelve con su token y los descarga en una carpeta "Liked Songs - Lu" (la UI muestra el nombre traducido)

### Requirement: Quién pidió qué
Cada pedido MUST registrar quién lo hizo, la colección de origen y las opciones. Cada canción encolada
MUST quedar asociada a su pedido.

#### Scenario: Cola compartida
- **GIVEN** Martín pidió 5 canciones y Lu pidió 2
- **WHEN** cualquiera pide `GET /api/queue`
- **THEN** ve las 7 canciones agrupadas por estado (descargando, comparando, buscando, en cola), cada una con el nombre de quien la pidió

### Requirement: Opciones del pedido
`options` MUST aceptar `enhancedRetries` (más intentos) y `extendCount` (sumar N canciones parecidas
con el modelo de next-track, usando como semillas la lista ya resuelta). Workers, chunk y rango MUST
NOT ser obligatorios: se usan los defaults del servidor, y solo un admin puede sobrescribirlos.

#### Scenario: Miembro intenta fijar workers
- **GIVEN** Lu tiene rol `member`
- **WHEN** manda un pedido con `workerCount: 8`
- **THEN** el pedido se procesa con el default del servidor e ignora `workerCount`

#### Scenario: Extender con canciones parecidas
- **GIVEN** Gonik pide "Late Night Drive" con `extendCount: 30`
- **WHEN** se procesa el pedido
- **THEN** se encolan las que faltan más 30 canciones generadas, en la carpeta "(extended)"

### Requirement: Reintentar una canción
Un pedido con `trackIds` de canciones `failed` y `enhancedRetries: true` MUST volver a buscarlas con
más intentos y timeouts más largos.

#### Scenario: Reintento con más intentos
- **GIVEN** "Redbone" está `failed`
- **WHEN** Lu toca "Buscar de nuevo con más intentos"
- **THEN** la canción pasa a `queued` a su nombre con `enhancedRetries`

### Requirement: Usar un candidato rechazado
Cualquier persona con sesión MUST poder elegir un candidato rechazado de una canción `failed`
(`POST /api/tracks/by-spotify/{spotifyId}/accept` con `candidateId`). El sistema MUST descargar ese
archivo y registrar el veredicto manual como un juicio más (`judge: "manual"`, con quién lo eligió).

#### Scenario: Usar igual una versión en vivo
- **GIVEN** "Redbone" falló y uno de sus candidatos es una versión en vivo (`wrong_version`)
- **WHEN** Gonik elige "Usar igual" sobre ese candidato
- **THEN** la canción pasa a `downloading` con ese archivo y su detalle de juicio muestra el veredicto manual de Gonik
