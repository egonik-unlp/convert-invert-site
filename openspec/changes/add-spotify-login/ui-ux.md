# UI/UX: add-spotify-login

**Estado:** Aplica

**Justificación si "No aplica":** —

## Componentes y flujos

Este change agrega solo la superficie mínima de auth. La barra lateral con la biblioteca y el resto del
rediseño viven en `update-ui-redesign`.

| Componente | Cambio | Estados |
|---|---|---|
| `LoginScreen` (nuevo) | Wordmark, una línea ("Tu música de Spotify, en tu disco."), botón "Entrar con Spotify", nota de invitación, selector de idioma | default · volviendo del callback con `?error=not_invited` (muestra la nota en rojo) · `?error=spotify` (Spotify falló, "Probá de nuevo") |
| Menú de perfil (nuevo, en el header actual) | Avatar + nombre; ítems "Idioma" y "Cerrar sesión" | abierto · cerrado |
| `Dashboard` (`graph://node:Dashboard`) | Gate: sin sesión → `LoginScreen`; miembros no ven Manage / Logs / Judgements | booting · sin sesión · miembro · admin |
| Manejo de 401 | Cualquier 401 vuelve a `LoginScreen` sin perder el hash de la vista actual | — |

Flujo: abrir la app → si no hay sesión, `LoginScreen` → "Entrar con Spotify" → Spotify → callback →
de vuelta en la vista en la que estaba (el hash se preserva en el `state` de OAuth).

## Wireframes / mockups

Maqueta interactiva (pantalla de login en el menú de perfil → "Cerrar sesión"):
https://claude.ai/artifact/QtmsGMSjGp6dS8Up6ygpUg

```
        convert/invert

        Tu música de Spotify,
        en tu disco.

        [      Entrar con Spotify      ]

        Solo para personas invitadas. Si no
        podés entrar, pedile acceso a Gonik.

        [ Español ][ English ]
```

## Accesibilidad

| Aspecto | Decisión |
|---|---|
| Roles ARIA | `LoginScreen` es un `<main>` con `<h1>` (wordmark). El botón de login es un `<a>` real a `/api/auth/login`. Menú de perfil con `aria-haspopup="menu"` y items `role="menuitem"` (Radix `DropdownMenu`) |
| Navegación por teclado | Login alcanzable con Tab en primer lugar; menú de perfil abre con Enter/Espacio, cierra con Escape y devuelve el foco al trigger |
| Foco visible | Reusa el anillo de foco de `components/ui/button` |
| Contraste | Texto de la nota ≥ 4.5:1 sobre el fondo en ambos temas; el error usa el token `--bad` validado en ambos temas |
| Lectores de pantalla | El error de callback se anuncia con `role="alert"` |
