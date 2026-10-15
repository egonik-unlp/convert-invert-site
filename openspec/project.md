# Project Context

<!--
  Template stub. Reemplazá los <TODO> con el contexto de tu proyecto.
  Este archivo lo lee el agente al generar context.md — mantenelo al día.
-->

## Purpose

<TODO: 1-2 frases sobre qué hace este producto y para quién.>

## Tech Stack

<TODO: runtime, framework HTTP, DB, librerías clave.>

## Documentation & Spec Stack

Este repo usa el harness SDD de tres capas — **consultar en este orden antes de explorar código**:

1. **Graphify** (`<package>/graphify-out/`) — grafo vivo del código. Query vía MCP `graphify`
   (`query_graph`, `get_node`, `get_neighbors`, `shortest_path`; configurado en `.mcp.json`); fallback `GRAPH_REPORT.md`.
2. **OpenSpec** (`openspec/specs/<capability>/spec.md`) — contrato funcional actual. Los changes pasan por
   `openspec/changes/<id>/` con el schema `sdd-with-knowledge` (6 artefactos).
3. **`knowledge/`** — contexto humano (decisiones, lore, convenciones), organizado en 3 capas:
   `knowledge/INDEX.md` (índice de módulos, entry point) → `knowledge/modules/<m>/INDEX.md` (navegación por
   intención: tabla "¿Qué quiero hacer?" intent→flow) → `knowledge/modules/<m>/use-cases/<capability>/`
   (contenido: spec/flow/decisions/notes; 1:1 con `openspec/specs/<capability>/`, resuelto por glob).

Regla divisoria: lo que Graphify responde (estructura) **no** se escribe en `knowledge/`.
Flujo completo en `openspec/README.md`; reglas duras en `openspec/CONVENTIONS.md`.

## Project Conventions

<TODO: code style, patrones de arquitectura, naming, testing, git workflow.>

## Domain Context

<TODO: entidades clave y sus relaciones, reglas de dominio no obvias.>

## Important Constraints

<TODO: restricciones operativas, invariantes críticas, gotchas de deploy.>
