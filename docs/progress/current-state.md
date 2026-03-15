# Current Repository State

Date: 2026-03-15
Status: microarchitecture frozen / RTL-ready

## Executive summary

The repository has completed architecture exploration (Sprint 01) and microarchitecture design (Sprint 02). The architecture baseline is frozen (INT8/INT32, 64x64 tile, 128 KiB 8-bank scratchpad, 8-opcode tensor ISA) and all blocks have signal-level interface specs, verification targets, and physical-awareness notes.

Block-level microarchitecture is defined for: MAC lane and array (3-stage pipeline, 16 lanes), scratchpad (8 banks, priority arbiter), DMA engine (16-byte burst), decoder (1-cycle fault detection), command queue controller, tile scheduler (10-state FSM), vector/softmax unit (4-stage dedicated pipeline with shift-add exp approximation), and debug infrastructure (4 performance counters, 8 probe points). A verification matrix maps 73 planned verification items across Sprints 03-07.

The codebase does **not** yet contain RTL implementations for any of these blocks, Caravel integration, OpenRAM macros, formal harnesses, compiler lowering, or firmware.

## Implemented baseline

| Area | Current status | Evidence |
| --- | --- | --- |
| Repository structure | Starter scaffold established | [README](../../README.md) |
| Dev environment | Containerized environment with Verilator, Yosys, nextpnr, OpenLane Python package, Python ML stack, RISC-V toolchain, and explicit `pytest` support for `make test` | [.devcontainer/devcontainer.json](../../.devcontainer/devcontainer.json), [docker/Dockerfile](../../docker/Dockerfile) |
| Bootstrap validation | `make doctor` checks required tools and reports optional later-sprint gaps | [Makefile](../../Makefile), [scripts/bootstrap_doctor.py](../../scripts/bootstrap_doctor.py) |
| CI | Bootstrap, lint, and cocotb test workflow exists | [.github/workflows/test.yml](../../.github/workflows/test.yml) |
| Project intake | Issue templates exist for architecture, implementation, and verification work | [.github/ISSUE_TEMPLATE/architecture-study.yml](../../.github/ISSUE_TEMPLATE/architecture-study.yml), [.github/ISSUE_TEMPLATE/implementation-task.yml](../../.github/ISSUE_TEMPLATE/implementation-task.yml), [.github/ISSUE_TEMPLATE/verification-task.yml](../../.github/ISSUE_TEMPLATE/verification-task.yml) |
| RTL | Single placeholder module only | [rtl/attention_stub.sv](../../rtl/attention_stub.sv) |
| Golden model | Expanded: float, quantized, and tiled-quantized attention with online softmax, precision configs, comparison utilities | [sim/reference_attention.py](../../sim/reference_attention.py) |
| Performance model | Analytical: tile sweeps, DMA overlap sensitivity, scratchpad feasibility | [sim/performance_model.py](../../sim/performance_model.py) |
| Numeric study | Automated: 15 tests covering quantized accuracy, tiled agreement, and edge cases | [sim/test_numeric_study.py](../../sim/test_numeric_study.py) |
| Architecture | Frozen baseline: INT8/INT32, 64x64 tile, 128 KiB scratchpad, 8-opcode ISA | [architecture/](architecture/), [decisions/](decisions/) |
| Microarchitecture | All blocks spec'd: compute, memory, control, vector/softmax, debug, interfaces | [microarchitecture/](microarchitecture/) |
| Verification plan | Comparison hierarchy, scoreboard structure, test vectors, formal targets defined | [reports/2026-03-15-verification-plan.md](reports/2026-03-15-verification-plan.md) |
| Verification matrix | 73 items across 10 blocks mapped to Sprints 03-07 | [reports/2026-03-15-verification-matrix.md](reports/2026-03-15-verification-matrix.md) |
| Physical awareness | Area estimates, clock/reset conventions, SKY130 technology notes | [microarchitecture/physical-awareness.md](microarchitecture/physical-awareness.md) |
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
- No performance-modeling scripts beyond the analytical model. No cycle-accurate or RTL-derived benchmark reports yet.

## Available starting points

- `make doctor` validates the Sprint 00 bootstrap baseline and flags optional environment gaps.
- `make lint` checks SystemVerilog sources with Verilator.
- `make test` runs the Python/cocotb-based simulation path.
- `make fpga ICE40_ARCH=... ICE40_PACKAGE=...` exercises the current starter iCE40 flow.
- `make gds PDK_ROOT=$PDK_ROOT` exercises the OpenLane smoke path for the placeholder design.

## Implications for planning

- Sprints 03-05 (MAC RTL, memory RTL, vector RTL) can proceed in parallel with frozen interfaces.
- Each block has signal-level interface tables, verification targets, and golden-model checkpoints.
- The verification matrix provides a concrete test plan: 54 unit tests, 16 formal properties, 3 integration tests.
- Physical-awareness notes identify MAC lane count and scratchpad capacity as the parameters most likely to change after synthesis.
- Caravel integration must be planned as a new workstream, because the repository does not yet contain a Caravel subtree.

## Reference reports

- [2026-03-15 Baseline Repo Audit](reports/2026-03-15-baseline-repo-audit.md) (Sprint 00)
- [2026-03-15 Sprint 00 Bootstrap](reports/2026-03-15-sprint-00-bootstrap.md) (Sprint 00)
- [2026-03-15 Architecture Study](reports/2026-03-15-architecture-study.md) (Sprint 01)
- [2026-03-15 Verification Plan](reports/2026-03-15-verification-plan.md) (Sprint 01)
- [2026-03-15 Verification Matrix](reports/2026-03-15-verification-matrix.md) (Sprint 02)
