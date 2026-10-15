# SDD Flow

Flujo de Spec-Driven Development (SDD) construido sobre [OpenSpec](https://github.com/Fission-AI/OpenSpec)
con capas propias: integración **Graphify** (grafo de conocimiento del código) + sincronización a
`knowledge/` (lore curado) vía **documenter**.

> **Esto NO es OpenSpec vanilla.** El namespace `/opsx:` se mantiene por compatibilidad, pero los
> artefactos, las reglas y el ciclo son específicos de este harness. Si una doc upstream contradice esto,
> manda este README.
>
> **Template.** Este archivo viene de `packages/snappec`. Reemplazá `<package>` por el nombre del
> paquete/repo instrumentado por Graphify en tu proyecto.

---

## Ciclo completo

```
/opsx:explore (opcional)
       │
       ▼
/opsx:propose <name>
       │ genera, en orden:
       │   context.md → proposal.md → specs.md → design.md → ui-ux.md → tasks.md
       ▼
/opsx:refresh-context <name>   (opcional, si el grafo cambió antes de apply)
       │
       ▼
/opsx:apply <name>
       │ implementa las tasks
       ▼
/opsx:archive <name>
       │ valida + mueve a archive/ + actualiza openspec/specs/
       │ + auto-invoca /documenter distill <dated-change-id>
       ▼
knowledge/modules/<module>/use-cases/<capability>/   ← sincronizado (módulo resuelto por glob)
```

---

## Los 6 artefactos

Cada change vive en `openspec/changes/<name>/`. Se generan en orden — cada uno depende del anterior.
Definición canónica en [schemas/sdd-with-knowledge/schema.yaml](schemas/sdd-with-knowledge/schema.yaml).

| # | Artefacto | Propósito | Requires |
|---|---|---|---|
| 1 | `context.md` | Subgrafo Graphify + archivos afectados + knowledge aplicable + riesgos. **Base de los otros 5.** | — |
| 2 | `proposal.md` | Why / Scope / Impact / Non-goals. Referencia nodos del grafo (`graph://node:X`). | `context` |
| 3 | `specs.md` | Delta spec `ADDED`/`MODIFIED`/`REMOVED Requirements`. Cada uno con ≥1 scenario Given/When/Then. | `proposal` |
| 4 | `design.md` | Approach técnico. Decisiones con rationale — `distill` las lleva a `knowledge/` post-archive. | `specs` |
| 5 | `ui-ux.md` | Primera línea = veredicto: `Aplica` o `No aplica — backend-only` + justificación. | `design` |
| 6 | `tasks.md` | Checklist. Última task: `/documenter distill <dated-change-id>` (auto-ejecutada por `archive`). | `ui-ux` |

---

## Los 5 comandos

Viven en [.claude/commands/opsx/](../.claude/commands/opsx/).

| Comando | Cuándo | Qué hace |
|---|---|---|
| `/opsx:explore` | Antes de proponer, si no sabés por dónde empezar | Thinking partner. No genera artefactos. |
| `/opsx:propose <name>` | Para abrir un change | Crea `openspec/changes/<name>/` y genera los 6 artefactos en orden. |
| `/opsx:refresh-context <name>` | Si el grafo se movió entre `propose` y `apply` | Regenera solo `context.md`. No toca los otros 5. |
| `/opsx:apply <name>` | Para implementar | Ejecuta las tasks, leyendo `context.md` y `design.md`. |
| `/opsx:archive <name>` | Cuando el change está listo | Valida, mueve a archive (con fecha) y **auto-invoca `/documenter distill <dated-id>`**. |

---

## Navegación: 3 capas

`knowledge/` se organiza en tres capas, de lo general a lo específico:

```
knowledge/INDEX.md                              # 1. índice de módulos (entry point)
knowledge/modules/<module>/INDEX.md             # 2. navegación del módulo: tabla "¿Qué quiero hacer?" (intent → flow)
knowledge/modules/<module>/use-cases/<cap>/     # 3. contenido del use-case (spec/flow/decisions/notes)
```

El **módulo** es la unidad de navegación/dominio (agrupa N use-cases, con diagrama de alto nivel y notas
transversales); el **use-case** es la unidad de contrato/cambio.

## Convención capability ↔ use-case

**Regla 1:1**: el slug en `openspec/specs/<capability>/` coincide con el use-case **anidado**
`knowledge/modules/<module>/use-cases/<capability>/`. El slug es **único globalmente** (lo garantiza
`openspec/specs/` plano), así que `distill` resuelve la ubicación por **glob**
`knowledge/modules/*/use-cases/<capability>/` (0 = nueva, 1 = existente, >1 = error). La **ubicación es la
membresía** — no hay frontmatter `module:`; mover de módulo es `git mv`. Los **módulos** no tienen slug en
`openspec/specs/` y no sincronizan por nombre; solo los use-cases dentro lo hacen.

### Archivos por use-case en `knowledge/`

Cada `knowledge/modules/<module>/use-cases/<capability>/` agrupa cuatro archivos, separados por **propósito**
(no por estructura de código — eso lo responde Graphify):

| Archivo | Responde | Modo |
|---|---|---|
| `spec.md` | **QUÉ** debe cumplirse (contrato narrativo, sync con `openspec/specs/`) | reference-ish |
| `flow.md` | **CÓMO** funciona end-to-end y **POR QUÉ** del comportamiento (flujo funcional + diagrama Mermaid) | explanation |
| `decisions.md` | **POR QUÉ** se eligió esta solución sobre alternativas (opcional) | explanation |
| `notes.md` | lore, gotchas, TODOs no derivables | — |

> **`flow.md` NO es un 7º artefacto del change.** Los 6 artefactos de `/opsx:propose` son fijos. `flow.md` es un
> destino de `knowledge/` que `documenter distill` **deriva** post-archive (de `proposal`/`design`/`specs`/`ui-ux`),
> traducido a lenguaje funcional. Es **obligatorio** y lleva veredicto en su 1ª línea (`Aplica` / `No aplica`).
> La prosa es la fuente de verdad; el diagrama Mermaid es una vista derivada. Detalle en
> [.claude/skills/documenter/SKILL.md](../.claude/skills/documenter/SKILL.md).

---

## Integración Graphify

El grafo del código vive en `<package>/graphify-out/` y se reconstruye automáticamente vía git hooks
(`.githooks/post-commit`, `.githooks/post-checkout` — instalados por el setup del harness).

**Cómo consultarlo**:
1. **Preferido**: Graphify MCP, tools `query_graph`, `get_node`, `get_neighbors`, `shortest_path`.
2. **Fallback**: leer `<package>/graphify-out/GRAPH_REPORT.md`.
3. **Código directo**: solo si lo anterior no alcanza, scoped al subgrafo.

**Setup**: el harness deja el MCP configurado en `.mcp.json` (server `graphify` → `scripts/graphify-mcp.sh`,
que resuelve el intérprete en runtime). Requiere `graphifyy` instalado y el grafo construido; si falta,
se usa el fallback `GRAPH_REPORT.md`.

---

## Integración documenter

[.claude/skills/documenter/SKILL.md](../.claude/skills/documenter/SKILL.md) mantiene `knowledge/`:

| Subcomando | Cuándo | Qué hace |
|---|---|---|
| `/documenter bootstrap` | Al inicializar el repo | Crea el árbol de `knowledge/` (INDEX global + `modules/`; siembra módulos desde comunidades Graphify si están). |
| `/documenter update` | Manual, ante sospecha de drift | Detecta divergencia vs git log, propone edits. Humano en el loop. |
| `/documenter distill <id>` | Auto post-archive; manual para re-runs | Sincroniza specs/decisiones/lore al use-case (`knowledge/modules/<m>/use-cases/<capability>/`, resuelto por glob) + su `INDEX.md` de módulo. |

---

## Cosas que NO van acá

- **Estructura del código** (entry points, dependencias) → Graphify. No documentar a mano.
- **Git history** → `git log` / archive.
- **State in-progress** → `openspec/changes/<name>/` mientras existe.
- **Lore funcional permanente** → `knowledge/`. No en `openspec/specs/` (esos son contratos formales).

---

## Referencias

- Schema: [schemas/sdd-with-knowledge/schema.yaml](schemas/sdd-with-knowledge/schema.yaml)
- Config con context+rules: [config.yaml](config.yaml)
- Reglas duras y edge cases: [CONVENTIONS.md](CONVENTIONS.md)
- Setup e instalación del harness: [../README.md](../README.md)
