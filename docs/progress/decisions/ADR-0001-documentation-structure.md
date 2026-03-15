# ADR-0001 - Documentation Structure

Date: 2026-03-15
Status: accepted

## Context

The project spans architecture exploration, RTL, formal, FPGA, Caravel integration, physical design, tapeout, and post-silicon work. The repository already declares `docs/` as the location for design notes and project documentation, but it did not yet contain a durable structure for progress tracking, decision logging, and evidence capture.

## Decision

Adopt `docs/progress/` as the persistent project-tracking tree and organize it into the following buckets:

- `architecture/` for system-level intent and performance modeling
- `microarchitecture/` for block-level implementation specs
- `decisions/` for ADRs
- `reports/` for dated evidence and milestone results
- `templates/` for reusable planning and reporting formats
- `sprints/` for sprint-by-sprint execution plans

Also adopt these naming rules:

- `master-plan.md` is the top-level roadmap
- `current-state.md` is the living repository baseline
- sprint docs use `sprint-XX-name.md`
- ADRs use `ADR-XXXX-name.md`
- reports use dated filenames when they capture a specific milestone or run

## Rationale

This structure matches the repository's existing documentation convention, scales across the full silicon program, and keeps planning artifacts close to the code they describe. It also avoids adding a separate documentation toolchain before the project needs one.

## Alternatives Considered

- create a new top-level `progress/` directory: rejected because `README.md` already assigns documentation to `docs/`
- keep one monolithic roadmap file only: rejected because architecture, reports, decisions, and sprint tracking would become hard to maintain
- introduce a documentation site generator immediately: rejected because the current project stage benefits more from lightweight Markdown tracked directly in git

## Consequences

- contributors have a clear place to add roadmap, report, and decision content
- sprint docs can evolve independently without bloating the master plan
- maintaining link integrity becomes an explicit documentation responsibility
- future automation can index this structure without reorganizing the repository again

## Follow-Up

- keep `README.md` linked to the progress hub for discoverability
- use the templates in `templates/` for all new sprint, ADR, and report additions
- update `current-state.md` whenever the implemented baseline changes materially
