# Current Repository State

Date: 2026-03-15
Status: scaffold / pre-architecture-freeze

## Executive summary

The repository currently provides a clean starter scaffold for an open-silicon attention-accelerator project, not a full transformer accelerator implementation. It already supports reproducible development, a bootstrap doctor check, smoke-test simulation, a placeholder FPGA path, and an OpenLane smoke flow, which is enough to begin disciplined architecture and implementation work.

The codebase does **not** yet contain the planned tiled attention datapath, Caravel wrapper, Wishbone integration, OpenRAM-generated scratchpad macros, formal harnesses, compiler lowering flow, or firmware/runtime stack described in the long-term roadmap.

## Implemented baseline

| Area | Current status | Evidence |
| --- | --- | --- |
| Repository structure | Starter scaffold established | [README](../../README.md) |
| Dev environment | Containerized environment with Verilator, Yosys, nextpnr, OpenLane Python package, Python ML stack, RISC-V toolchain, and explicit `pytest` support for `make test` | [.devcontainer/devcontainer.json](../../.devcontainer/devcontainer.json), [docker/Dockerfile](../../docker/Dockerfile) |
| Bootstrap validation | `make doctor` checks required tools and reports optional later-sprint gaps | [Makefile](../../Makefile), [scripts/bootstrap_doctor.py](../../scripts/bootstrap_doctor.py) |
| CI | Bootstrap, lint, and cocotb test workflow exists | [.github/workflows/test.yml](../../.github/workflows/test.yml) |
| Project intake | Issue templates exist for architecture, implementation, and verification work | [.github/ISSUE_TEMPLATE/architecture-study.yml](../../.github/ISSUE_TEMPLATE/architecture-study.yml), [.github/ISSUE_TEMPLATE/implementation-task.yml](../../.github/ISSUE_TEMPLATE/implementation-task.yml), [.github/ISSUE_TEMPLATE/verification-task.yml](../../.github/ISSUE_TEMPLATE/verification-task.yml) |
| RTL | Single placeholder module only | [rtl/attention_stub.sv](../../rtl/attention_stub.sv) |
| Golden model | Minimal NumPy attention reference exists | [sim/reference_attention.py](../../sim/reference_attention.py) |
| Simulation | C++ Verilator smoke path and cocotb test skeleton exist | [sim/main.cpp](../../sim/main.cpp), [sim/test_attention.py](../../sim/test_attention.py) |
| FPGA | Placeholder README only; no board-specific wrapper or constraints checked in | [fpga/README.md](../../fpga/README.md) |
| ASIC flow | OpenLane smoke configuration for the stub module exists | [openlane/config.json](../../openlane/config.json) |
| Make targets | Core commands wired for lint, sim, test, fpga, and gds flows | [Makefile](../../Makefile) |

## What is missing relative to the target program

- No `attn_core` or sub-block RTL such as MAC array, scratchpad, DMA, scheduler, vector unit, softmax unit, or ISA decoder.
- No Caravel-specific directories, wrappers, Wishbone bridge logic, logic-analyzer hookups, or user project integration collateral.
- No OpenRAM configuration or generated SRAM macros.
- No SymbiYosys formal setup or module property suites.
- No integrated OpenROAD or OpenSTA backend analysis flow beyond the current OpenLane smoke path.
- No compiler lowering or ONNX-to-command pipeline in [compiler/](../../compiler/).
- No firmware driver or runtime implementation in [software/](../../software/).
- No board-specific FPGA design collateral beyond a placeholder README.
- No performance-modeling scripts, architecture sweeps, or benchmark reports.

## Available starting points

- `make doctor` validates the Sprint 00 bootstrap baseline and flags optional environment gaps.
- `make lint` checks SystemVerilog sources with Verilator.
- `make test` runs the Python/cocotb-based simulation path.
- `make fpga ICE40_ARCH=... ICE40_PACKAGE=...` exercises the current starter iCE40 flow.
- `make gds PDK_ROOT=$PDK_ROOT` exercises the OpenLane smoke path for the placeholder design.

## Implications for planning

- Sprint 0 and Sprint 1 should treat the existing code as bootstrap infrastructure, not as partially completed accelerator RTL.
- Architecture and microarchitecture docs must distinguish clearly between current implementation and target intent.
- Caravel integration must be planned as a new workstream, because the repository does not yet contain a Caravel subtree.
- Verification strategy must start with unit-level scaffolding and golden-model expansion before system-level comparisons become meaningful.

## Reference report

See the dated baseline audit in [reports/2026-03-15-baseline-repo-audit.md](reports/2026-03-15-baseline-repo-audit.md) and the Sprint 00 completion snapshot in [reports/2026-03-15-sprint-00-bootstrap.md](reports/2026-03-15-sprint-00-bootstrap.md).
