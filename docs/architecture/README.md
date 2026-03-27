# Architecture Documentation

This folder contains the formal architecture set for KashCube.

The documents here are seeded from the implementation-backed material in `docs/codebase/` and describe the current system shape, runtime boundaries, major decisions, and quality attributes.

## Reading Order

1. `technical/TECHNICAL_ARCHITECTURE.md`
   - software architecture document (SAD) overview
   - architectural principles
   - runtime structure and traceability
2. `technical/SYSTEM_CONTEXT.md`
   - external actors, trust boundaries, and system context
3. `technical/COMPONENT_MODEL.md`
   - structural decomposition and component responsibilities
4. `technical/DATA_FLOW_DIAGRAMS.md`
   - core runtime and business data flows
5. `technical/DEPLOYMENT_AND_RUNTIME_TOPOLOGY.md`
   - deployed units, process topology, and runtime connections
6. `technical/TECHNOLOGY_STACK.md`
   - framework, package, and platform choices
7. `technical/QUALITY_ATTRIBUTES.md`
   - quality scenarios and architectural responses
8. `decisions/ARCHITECTURE_DECISIONS.md`
   - ADR index and major architectural decisions
9. `privacy/PRIVACY_ARCHITECTURE.md`
   - privacy-first constraints and storage model

## Relationship To As-Built Docs

- `docs/codebase/` remains the implementation-anchored source for code archaeology.
- `docs/architecture/` turns that evidence into a formal architecture narrative.
- When runtime behavior changes, update the as-built docs first, then refresh the formal documents that depend on them.

## Source Anchors

Primary implementation-backed inputs for this set:

- `docs/codebase/ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/BOOT_AND_STARTUP_AS_BUILT.md`
- `docs/codebase/architecture/APP_SHELL_AND_NAVIGATION_AS_BUILT.md`
- `docs/codebase/architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md`
- `docs/codebase/architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md`
- `docs/codebase/DATABASE_AS_BUILT.md`
- `docs/codebase/SYNC_AND_IDENTITY_AS_BUILT.md`