# Current Repository State

Date: 2026-03-15
Status: architecture frozen / pre-RTL

## Executive summary

The repository has completed architecture exploration (Sprint 01). The first credible architecture baseline is frozen: INT8 operands with INT32 accumulation, 64x64 tile shape, 128 KiB 8-bank scratchpad, and an 8-opcode tensor ISA with MMIO command queue control.

The expanded golden model supports tiled execution with online softmax, matching the planned hardware dataflow. An analytical performance model validates the chosen baseline at 96.9% MAC utilization. Numeric studies confirm the INT8 quantization error budget is acceptable (cosine > 0.90).

The codebase does **not** yet contain the planned tiled attention datapath RTL, Caravel wrapper, Wishbone integration, OpenRAM-generated scratchpad macros, formal harnesses, compiler lowering flow, or firmware/runtime stack described in the long-term roadmap.

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
| Verification plan | Comparison hierarchy, scoreboard structure, test vectors, formal targets defined | [reports/2026-03-15-verification-plan.md](reports/2026-03-15-verification-plan.md) |
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

- Sprint 02 (microarchitecture) can now proceed with frozen architecture parameters.
- RTL implementation in Sprints 03-05 has clear golden-model checkpoints and numeric thresholds.
- The verification plan defines scoreboard structure and test vectors for each RTL block.
- Caravel integration must be planned as a new workstream, because the repository does not yet contain a Caravel subtree.
- The performance model provides baseline utilization and latency targets for RTL to match.

## Reference reports

- [2026-03-15 Baseline Repo Audit](reports/2026-03-15-baseline-repo-audit.md) (Sprint 00)
- [2026-03-15 Sprint 00 Bootstrap](reports/2026-03-15-sprint-00-bootstrap.md) (Sprint 00)
- [2026-03-15 Architecture Study](reports/2026-03-15-architecture-study.md) (Sprint 01)
- [2026-03-15 Verification Plan](reports/2026-03-15-verification-plan.md) (Sprint 01)
