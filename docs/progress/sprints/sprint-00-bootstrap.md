# Sprint 00 - Repository Bootstrap

Status: done

## Objective

Turn the current scaffold into a disciplined execution baseline with documented environment assumptions, validated smoke flows, and a stable progress-tracking structure.

## Deliverables

- `docs/progress/` documentation tree and baseline audit
- validated development-environment assumptions for `.devcontainer/`, `docker/`, and `Makefile` flows
- documented CI expectations for `make lint` and `make test`
- known-gap list for FPGA, OpenLane, and future Caravel work

## Dependencies

- current repository scaffold only
- host access to Docker and a valid `PDK_ROOT` for OpenLane smoke checks

## Parallelization Note

All lanes can begin immediately because they consume the existing scaffold rather than waiting on new RTL.

## Parallel Workstreams

### Documentation and program lane

- publish the progress-tracking hierarchy under `docs/progress/`
- record the repository baseline and initial risks
- define naming conventions for sprints, ADRs, and reports

### Environment and tooling lane

- audit `.devcontainer/devcontainer.json` and `docker/Dockerfile` against expected EDA and software needs
- document required host-side setup such as `PDK_ROOT` and Docker access
- identify missing future dependencies for formal, Caravel, and board-specific FPGA work

### Verification and CI lane

- confirm the intended role of `make lint` and `make test` as baseline checks
- document the minimum regression expectations before new RTL is merged
- outline how future formal and integration checks will plug into CI

### Flow validation lane

- record the placeholder status of the FPGA path in `fpga/`
- record the stub-only status of the OpenLane path in `openlane/`
- capture what must change before either path becomes implementation-grade

## Exit Criteria

- the baseline state of the repository is documented and linked from the progress index
- the environment assumptions and known gaps are explicit
- the team has a documented starting point for Sprint 1 architecture work

## Evidence To Capture

- [Baseline Repo Audit](../reports/2026-03-15-baseline-repo-audit.md)
- [Sprint 00 Bootstrap Report](../reports/2026-03-15-sprint-00-bootstrap.md)
- [Current State](../current-state.md)
- [Master Plan](../master-plan.md)

## Open Risks And Decisions

- host-side PDK and Docker access may differ between contributors
- placeholder flows may be mistaken for implementation-ready flows unless clearly labeled
- formal, Caravel, OpenRAM, and board-specific FPGA tooling remain planned follow-on work rather than Sprint 00 deliverables
