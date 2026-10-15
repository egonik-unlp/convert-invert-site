---
name: "OPSX: Refresh Context"
description: Regenerate context.md for an existing change using the current state of the graph and knowledge base
category: Workflow
tags: [workflow, context, graphify, experimental]
---

Regenerate `context.md` for an existing change, leaving the rest of the change artifacts untouched.

Use this when the codebase has moved between `/opsx:propose` and `/opsx:apply` and you want `context.md` to reflect the current state of the Graphify graph and `knowledge/` — without losing the manual edits in `proposal.md`, `specs.md`, `design.md`, `ui-ux.md`, or `tasks.md`.

> **Local customization** — this command is part of the Snappler SDD flow on top of OpenSpec. See [openspec/README.md](../../../openspec/README.md) and [openspec/CONVENTIONS.md](../../../openspec/CONVENTIONS.md).

---

**Input**: A change name after `/opsx:refresh-context` (e.g. `/opsx:refresh-context add-knowledge-base-v2`). If omitted, prompt for selection from active changes.

**Steps**

1. **Resolve the change**

   - If no name was provided, run `openspec list --json` and use the **AskUserQuestion tool** to let the user pick from active (non-archived) changes.
   - Verify `openspec/changes/<name>/context.md` exists. If not, fail with: "No previous `context.md` to refresh — run `/opsx:propose` first if this is a new change."

2. **Read the rest of the change for scope**

   - Read `openspec/changes/<name>/proposal.md` (mandatory) to identify which nodes / capabilities are in scope.
   - Read `openspec/changes/<name>/specs/` (if it exists) to enumerate capabilities affected.
   - The point: the refresh re-snapshots Graphify and knowledge **around the same scope** the change already defined. It does not re-discover scope from scratch.

3. **Re-consolidate context via Graphify + knowledge**

   - Query Graphify MCP using the nodes/capabilities derived from `proposal.md`:
     - `query_graph("<main feature/symbol>")`
     - `get_neighbors("<main node>")`
     - `shortest_path` for non-obvious cross-module relationships
   - Read knowledge in scope (resolve each use-case by glob `knowledge/modules/*/use-cases/<capability>/`):
     - `knowledge/modules/<m>/use-cases/<capability>/spec.md`, `flow.md`, `decisions.md`, `notes.md` for each capability touched
     - `knowledge/modules/<m>/INDEX.md` for the module's intent→flow navigation
     - `knowledge/decisions.md` for macro conflicts
     - `knowledge/conventions.md` if relevant

4. **Regenerate `context.md`**

   - Use the template at `openspec/schemas/sdd-with-knowledge/templates/context.md` as the structure.
   - Fill all sections: Nodos afectados, Archivos relevantes, Contexto knowledge, Riesgos identificados.
   - Apply the same `context:` and `rules:` constraints from `openspec/config.yaml` that `/opsx:propose` would apply — but do **not** copy them into the file.

5. **Show diff and confirm**

   - Show a unified diff between the previous `context.md` and the regenerated one.
   - Use the **AskUserQuestion tool** to confirm: "Write refreshed context.md? (yes / no / show full new file)".
   - On confirmation, overwrite `openspec/changes/<name>/context.md`.

6. **Heads-up about the rest of the change**

   After writing, print a reminder:
   > Context refreshed. The other artifacts (`proposal.md`, `specs.md`, `design.md`, `ui-ux.md`, `tasks.md`) were **not** modified. Review whether they're still valid against the new context. If they diverged significantly, consider re-running `/opsx:propose` or editing them by hand.

**Guardrails**
- **Never** touch `proposal.md`, `specs.md`, `design.md`, `ui-ux.md`, or `tasks.md`. This command's job is strictly `context.md`.
- If `proposal.md` is missing, fail — the refresh needs the existing scope as a seed and won't invent one.
- If Graphify MCP is not available, fall back to `agent-realstate/graphify-out/GRAPH_REPORT.md` and warn the user that the refresh is based on the last static report, not live MCP queries.
- This command does not run `openspec validate`. The user can run it manually after refreshing if they want to check coherence.

**Output On Success**

```
## Context Refreshed

**Change:** <change-name>
**File:** openspec/changes/<change-name>/context.md

Diff summary:
  - <N> nodes added to "Nodos afectados"
  - <N> nodes removed
  - <N> files changed in "Archivos relevantes"
  - Risks updated: <yes/no>

The other 5 artifacts were not modified.
Review them to ensure they're still consistent with the new context.
```

**Output On No-Op**

```
## Context Already Up-to-date

**Change:** <change-name>

The regenerated context.md matched the previous version. No changes written.
```
