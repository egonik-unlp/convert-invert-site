# Delta Spec: add-spotify-login

**Capability:** spotify-login
**Change:** add-spotify-login

## ADDED Requirements

### Requirement: Entrar con Spotify
El sistema MUST autenticar a las personas únicamente con su cuenta de Spotify (OAuth Authorization Code
con PKCE y `state`), y MUST rechazar a quien no esté invitado.

#### Scenario: Persona invitada entra por primera vez
- **GIVEN** un admin invitó el email `lu@example.com`
- **WHEN** Lu toca "Entrar con Spotify", autoriza la app y Spotify vuelve al callback con un `code` y un `state` válidos
- **THEN** el sistema crea su usuario vinculado a su Spotify id, abre una sesión y la redirige a la app

#### Scenario: Persona no invitada
- **GIVEN** el email de la cuenta de Spotify no está en la lista de invitados
- **WHEN** completa la autorización en Spotify
- **THEN** el sistema no crea sesión y muestra "Solo para personas invitadas. Si no podés entrar, pedile acceso a <admin>."

#### Scenario: Callback con state inválido
- **GIVEN** un callback cuyo `state` no coincide con el que se emitió al iniciar el login
- **WHEN** llega al servidor
- **THEN** el sistema responde error, no intercambia el `code` y no crea sesión

### Requirement: Sesión por cookie
El sistema MUST mantener la sesión con una cookie `HttpOnly`, `SameSite=Lax` (`Secure` configurable)
que contiene un token opaco. En la base MUST guardarse solo el hash del token. La sesión MUST vencer
después de 30 días sin uso.

#### Scenario: Request con sesión válida
- **GIVEN** una persona con sesión vigente
- **WHEN** el frontend llama a cualquier endpoint de `/api` con la cookie
- **THEN** el request se atiende como esa persona y se extiende el vencimiento de la sesión

#### Scenario: Sesión vencida
- **GIVEN** una sesión que no se usó en más de 30 días
- **WHEN** llega un request con esa cookie
- **THEN** el sistema responde 401 y el frontend muestra la pantalla de login

#### Scenario: Cerrar sesión
- **GIVEN** una persona con sesión vigente
- **WHEN** elige "Cerrar sesión"
- **THEN** el sistema invalida la sesión en la base y borra la cookie

### Requirement: Roles admin y miembro
Cada usuario MUST tener rol `admin` o `member`. Los endpoints operativos (workers, pausa/reanudación
de descargas, cambio de juez, registros, cancelación de descargas) MUST ser solo para admins.
`ADMIN_EMAILS` MUST definir los admins iniciales.

#### Scenario: Miembro llama un endpoint operativo
- **GIVEN** Lu tiene rol `member`
- **WHEN** llama `POST /api/pipeline/pause`
- **THEN** el sistema responde 403 y no cambia nada

#### Scenario: Admin inicial
- **GIVEN** `ADMIN_EMAILS` contiene el email de Gonik
- **WHEN** Gonik entra por primera vez
- **THEN** su usuario se crea con rol `admin` aunque nadie lo haya invitado

### Requirement: Invitar personas
Un admin MUST poder invitar por email, cambiar el rol de alguien y desactivar el acceso. Una persona
desactivada MUST perder sus sesiones.

#### Scenario: Desactivar a alguien
- **GIVEN** Martín tiene dos sesiones abiertas
- **WHEN** un admin desactiva su acceso
- **THEN** sus sesiones se invalidan y su próximo request responde 401

### Requirement: Token de servicio
El `X-API-Key` MUST seguir funcionando como token de servicio para scripts, con permisos de admin.
El frontend MUST NOT incluir el key en su bundle.

#### Scenario: Script con API key
- **GIVEN** un script que manda `X-API-Key` válido y no tiene cookie
- **WHEN** llama `GET /api/stats`
- **THEN** el request se atiende con permisos de admin

### Requirement: Guardar tokens de Spotify
El sistema MUST guardar el refresh token de cada usuario cifrado (AES-256-GCM, clave en `TOKEN_ENC_KEY`),
renovar el access token cuando vence, y MUST NOT exponer ninguno de los dos al frontend.

#### Scenario: Access token vencido
- **GIVEN** el access token de Lu venció
- **WHEN** el backend necesita leer su biblioteca
- **THEN** lo renueva con el refresh token, guarda el nuevo y sigue con el request sin que Lu lo note

#### Scenario: Refresh token revocado
- **GIVEN** Lu le quitó el acceso a la app desde su cuenta de Spotify
- **WHEN** el backend intenta renovar su token
- **THEN** el sistema cierra sus sesiones y la próxima vez le pide entrar de nuevo
