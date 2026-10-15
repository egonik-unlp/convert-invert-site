# SDD Conventions

Reglas duras del flujo. Para el flujo de punta a punta, leer primero [README.md](README.md). Este
documento resuelve edge cases y deja explícitas las decisiones de diseño.

> **Template.** Este archivo viene del harness `packages/snappec`. Los ejemplos son genéricos;
> adaptá los nombres a tu repo a medida que aparezcan capabilities reales.

---

## Naming

### Slug del change
- Formato: `kebab-case`.
- Prefijo verbo: `add-`, `replace-`, `remove-`, `refactor-`, `update-`, `fix-`.
- **No** se escribe la fecha a mano. `archive` agrega el prefijo `YYYY-MM-DD-` al mover a
  `openspec/changes/archive/`. Ejemplo: `add-foo` → archivado como `2026-05-26-add-foo`.

### Slug del capability
- Formato: `kebab-case`, sustantivo singular o frase corta (`user-auth`, `email-notifications`).
- **Regla 1:1**: el slug en `openspec/specs/<capability>/` = nombre exacto de la carpeta del use-case, que
  vive **anidado bajo un módulo**: `knowledge/modules/<module>/use-cases/<capability>/`. El slug es **único
  globalmente** (lo garantiza `openspec/specs/` plano), así que `/documenter distill` resuelve la ubicación
  por **glob** `knowledge/modules/*/use-cases/<capability>/` (0 hits = nueva; 1 = existente, in situ; >1 =
  error). La **ubicación es la membresía** — no hay frontmatter `module:`.
- Los **módulos** (`knowledge/modules/<module>/`) son capa de navegación: NO tienen slug en
  `openspec/specs/` y NO sincronizan por nombre. Solo los use-cases dentro de ellos lo hacen.
- El módulo reservado `_unsorted` aloja capabilities nuevas sin módulo resuelto; se mueven a su módulo
  definitivo con `git mv` (distill las re-encuentra por glob).
- Si tu repo tiene use-cases legacy sin spec viva en `openspec/specs/`, respetalos como historia. La regla
  1:1 aplica a capabilities **nuevas**, no retroactivamente.

---

## Validación pre-archive

`/opsx:archive` ejecuta, en orden:

1. `openspec validate <change-name>` (upstream) — debe pasar.
2. Cada artefacto debe estar en estado `done` (warning si no, no bloquea — se confirma al usuario).
3. `tasks.md` debe tener todas las tasks marcadas (warning si quedan abiertas — se confirma al usuario).
4. Para cada capability en delta specs: existe `knowledge/modules/*/use-cases/<capability>/` (glob, 0 o 1
   hit) o se va a crear vía `distill` (que la ubica en un módulo).
5. La **última task** en `tasks.md` es `post-archive: /documenter distill <dated-change-id>`, anotada como
   **auto-ejecutada por `/opsx:archive`**. Es recordatorio/fallback: el trigger real vive en `archive`.
   El re-run manual usa el id completo con fecha.

---

## Multi-capability changes

Un change puede tocar más de una capability:
- Un solo `proposal.md`, `design.md`, `ui-ux.md`, `tasks.md`.
- En `specs/`, carpetas separadas: `openspec/changes/<name>/specs/<capability-A>/`, `.../<capability-B>/`.
- El slug del change describe el **cambio transversal**, no una capability puntual.
- `archive` valida y sincroniza cada capability por separado contra su use-case (resuelto por glob
  `knowledge/modules/*/use-cases/<capability>/`).

---

## Deprecaciones (REMOVED Requirements)

- `openspec/specs/<capability>/spec.md` se actualiza eliminando el requirement.
- `knowledge/modules/<module>/use-cases/<capability>/spec.md` **no se borra automáticamente**:
  - Si todo el use-case queda deprecado, marcar `status: deprecated` en frontmatter y dejar el contenido
    como histórico.
  - Si solo se deprecan requirements parciales, dejar la spec narrativa cubriendo el comportamiento actual.
- Razón: `knowledge/` es contexto consultable; borrar a la primera deprecación pierde historia útil.

---

## Versionado de specs

**No hay semver de capabilities.** El git history de `openspec/changes/archive/` es el versionado: cada
archive con fecha es un punto en la línea de tiempo de la capability. Es un non-goal explícito; se reabre
solo si hace falta consumir specs versionadas desde otro repo.

---

## Edge cases

### Change abortado a mitad de `apply`
- Borrar `openspec/changes/<name>/` a mano (`rm -rf`). **No usar `archive`** para "deshacer".

### Re-run de `/documenter distill`
- El change tiene que estar **archivado**. Comando: `/documenter distill <dated-change-id>` (nombre completo
  con fecha). Útil si rechazaste edits la primera vez.

### Re-run de `/opsx:propose` sobre un change existente
- Regenera los 6 artefactos perdiendo edits manuales. Si solo querés refrescar el contexto, usar el siguiente.

### Refresh de `context.md` sin perder el resto
- `/opsx:refresh-context <change-name>` — re-genera solo `context.md` consultando el grafo actual.
- Conserva `proposal/specs/design/ui-ux/tasks`. Tras refrescar, revisar que el resto siga siendo válido.

### Falla de auto-distill en `archive`
- El archive **igual completa** (move + sync de specs). Re-correr: `/documenter distill <dated-change-id>`.
- "Nothing to distill" en changes puramente operacionales (tooling/config) está OK.

---

## State queries durante el flujo

Se usa OpenSpec upstream directo desde CLI — no hay comandos custom:
- `openspec list` — changes activos.
- `openspec status --change <name> --json` — estado de artefactos.
- `openspec validate <name>` — validar (lo que corre `archive`).

---

## Commands del documenter

Set formal: `bootstrap`, `update`, `distill <change-id>`. Todos vía `/documenter <sub>`.
- `bootstrap` — una sola vez al inicializar un repo.
- `update` — a discreción cuando se sospecha drift.
- `distill` — auto desde `archive`; manual solo para re-runs.

No agregar más subcomandos sin discutir — el set está pensado para mantener el ciclo simple.

---

## Decisiones cerradas (registro)

| # | Tema | Resolución |
|---|---|---|
| 1 | Rol de `/opsx:explore` | Opcional, recomendado para changes grandes. No genera artefactos. |
| 2 | `context.md` refresh si cambia el grafo | Manual vía `/opsx:refresh-context`. Nunca auto-refresh. |
| 3 | `ui-ux.md` siempre o solo si aplica | Siempre. Veredicto obligatorio en la primera línea. |
| 4 | Falla a mitad de `apply` | Borrar `openspec/changes/<name>/` a mano. `archive` no se usa para deshacer. |
| 5 | Trigger de `documenter distill` | Automático en `archive` (con id dateado). Manual para re-runs. |
| 6 | Validación pre-archive | `openspec validate` + chequeo por glob de `knowledge/modules/*/use-cases/<slug>/`. |
| 7 | Multi-capability changes | Soportado: múltiples carpetas en `specs/`. |
| 8 | Namespace de comandos | `/opsx:` (5 comandos: explore, propose, refresh-context, apply, archive). Set fijo. |
| 9 | `flow.md` por use-case | Obligatorio en cada use-case, veredicto en la 1ª línea (`Aplica` / `No aplica — flujo trivial`). Modo *explanation*: flujo funcional en prosa numerada (canónica) + diagrama Mermaid (vista derivada). Refs por ancla estable (`graph://node:X` / símbolo), nunca por número de línea. Es destino de `documenter distill`, **NO** un 7º artefacto del change. Lleva además `Permisos` y `Casos de error / rechazo` (vista tabular derivada de scenarios). |
| 10 | Módulos contienen use-cases | El árbol de `knowledge/` es anidado: `modules/<module>/use-cases/<capability>/`. El módulo es navegación/dominio (con `INDEX.md`: resumen + diagrama + tabla intent→flow + notas transversales); el use-case es contrato/cambio (1:1 con `openspec/specs/`). **Ubicación = membresía** (sin frontmatter `module:`); `distill` resuelve por **glob** del slug único. `_unsorted` reservado para nuevos sin clasificar. Los módulos NO sincronizan por nombre. Sin 4º subcomando: se extienden `bootstrap` (crea `modules/` + INDEX global; siembra desde comunidades Graphify) y `distill`. Citación por ancla estable. |

Meta-arquitectura:
- La lógica del proyecto vive en `openspec/config.yaml` (`context:` + `rules:`) + templates. **No** se duplica
  en las skills `openspec-*`.
- Las skills `openspec-*` son forks mínimos de vanilla.
