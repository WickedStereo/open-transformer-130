# Progress Tracking

This directory is the program-management and technical-decision hub for the transformer attention accelerator effort. It is intentionally plain Markdown so progress can be reviewed in git alongside RTL, tooling, and verification changes.

## Core documents

- [Master Plan](master-plan.md): end-to-end roadmap from scaffold to post-silicon validation.
- [Current State](current-state.md): factual snapshot of what exists in the repository today.
- [Architecture](architecture/README.md): system-level architecture, ISA, memory hierarchy, and performance model.
- [Microarchitecture](microarchitecture/README.md): block-level implementation intent and interface contracts.
- [Decisions](decisions/README.md): ADR-style records for durable design choices.
- [Reports](reports/README.md): dated results, audits, and implementation evidence.
- [Sprint Plans](sprints/README.md): sprint-by-sprint execution plans with parallel workstreams.
- [Templates](templates/README.md): reusable templates for planning, ADRs, and result reporting.

## Working rules

- Update [current-state.md](current-state.md) when the implemented baseline changes materially.
- Add an ADR for decisions that affect interfaces, architecture, tool flow, or verification strategy.
- Add a dated report whenever a milestone produces measurable evidence such as synthesis, timing, FPGA, or verification results.
- Keep sprint docs actionable: each task should fit a contributor lane and identify its dependencies.
- Link to concrete repository paths wherever possible, especially for deliverables and evidence.

## Status vocabulary

- `planned`: documented but not started.
- `active`: currently in execution.
- `blocked`: waiting on an external dependency or earlier sprint output.
- `done`: completed with evidence linked.
- `superseded`: intentionally replaced by a newer plan or decision.

## Relationship to the repository

The root [README](../../README.md) describes the codebase as a starter scaffold. These docs preserve that truth while defining the path toward the full accelerator target, including architecture exploration, RTL, FPGA, Caravel integration, physical design, and post-silicon validation.
