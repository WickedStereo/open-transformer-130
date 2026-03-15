# Sprint 00 Bootstrap Report

Date: 2026-03-15
Report type: bootstrap
Revision: working tree
Owner: repository maintainers

## Objective

Capture the concrete repository changes that complete Sprint 00 bootstrap work and define the expected baseline before Sprint 01 architecture exploration begins.

## Scope

- development-environment validation
- CI baseline checks
- repository intake templates
- known-gap documentation for future FPGA, OpenLane, Caravel, and formal work

## Completed outputs

- Added `make doctor` as the bootstrap validation entrypoint in [Makefile](../../../Makefile).
- Added [scripts/bootstrap_doctor.py](../../../scripts/bootstrap_doctor.py) to check required tools, Python packages, and environment assumptions while reporting non-blocking later-sprint gaps.
- Added explicit `pytest` installation to [.devcontainer/devcontainer.json](../../../.devcontainer/devcontainer.json) and [docker/Dockerfile](../../../docker/Dockerfile) so the documented `make test` path is present in the dev environment.
- Expanded [.github/workflows/test.yml](../../../.github/workflows/test.yml) to run `make doctor` before lint and test, and aligned its installed packages more closely with the bootstrap toolchain.
- Added GitHub issue templates under [.github/ISSUE_TEMPLATE/](../../../.github/ISSUE_TEMPLATE/) for architecture studies, implementation tasks, and verification work.

## CI expectations

The expected baseline for repository changes after Sprint 00 is:

- `make doctor`
- `make lint`
- `make test`

These three checks define the default merge confidence for the current scaffold stage. They do not replace later FPGA, formal, Caravel, or physical-design evidence.

## Known non-blocking gaps

- No Caravel checkout, wrapper, or Wishbone integration is present yet.
- No board-specific FPGA wrapper or constraints are present yet.
- No OpenRAM flow or generated SRAM macros are present yet.
- No SymbiYosys, OpenROAD, or OpenSTA bootstrap integration is present yet.
- `make gds` remains a smoke path that depends on `PDK_ROOT`, Docker access, and the placeholder OpenLane configuration.

## Recommended Sprint 01 handoff

- Use `make doctor` as the first command after entering the devcontainer.
- Treat the new issue templates as the intake path for architecture studies and implementation work.
- Keep Sprint 01 focused on golden-model expansion, ISA freeze, and performance modeling rather than adding large RTL blocks early.

## Linked artifacts

- [Current State](../current-state.md)
- [Sprint 00 Plan](../sprints/sprint-00-bootstrap.md)
- [Baseline Repo Audit](2026-03-15-baseline-repo-audit.md)
