# Current Repository State

Date: 2026-03-15
Status: integrated prototype / de-risked baseline

## Executive summary

The repository now contains a real integrated `attn_core` baseline rather than a placeholder-only top. The current implementation supports a working `LOAD_TILE -> MATMUL -> SOFTMAX -> STORE_TILE` path over scratchpad-resident INT8 tiles, with the compute engine prefetching operands from scratchpad, the vector unit performing row-wise fixed-point softmax, and the DMA path honoring the documented 1-cycle scratchpad read latency.

The verification baseline is materially stronger than before:

- `make lint` passes.
- `make formal` passes locally with the bounded `cvc4`-backed proof suite.
- `make test` passes `29` cocotb regressions.
- The repo now includes standalone benches for `queue_ctrl`, `dma_engine`, `vector_unit`, `tile_scheduler`, `perf_counters`, and `compute_engine`, plus an end-to-end `attn_core` scoreboard test.
- Formal harnesses are attached under `formal/`, `make formal` now passes locally with solver-backed checks, and CI is configured to install `cvc4` and run the same bounded proof suite.

The repo is still not tapeout-ready. The integrated top is now backend-relevant, but the scratchpad is still backed by a behavioral model behind a macro-style wrapper, there is no OpenRAM-generated macro collateral yet, and the software/compiler/Caravel workstreams remain largely unimplemented.

## Implemented baseline

| Area | Current status | Evidence |
| --- | --- | --- |
| Repository structure | Working accelerator prototype with integrated RTL, tests, and backend entry points | [README](../../README.md) |
| Dev environment | Containerized environment with Verilator, Yosys, nextpnr, OpenLane Python package, and Python verification tooling | [.devcontainer/devcontainer.json](../../.devcontainer/devcontainer.json), [docker/Dockerfile](../../docker/Dockerfile) |
| Bootstrap validation | `make doctor` still checks required tools and reports optional gaps | [Makefile](../../Makefile), [scripts/bootstrap_doctor.py](../../scripts/bootstrap_doctor.py) |
| CI | Lint, cocotb regression, and formal targets are wired in workflow | [.github/workflows/test.yml](../../.github/workflows/test.yml) |
| RTL top | `attn_core` integrates MMIO, queue control, decoder, scheduler, DMA, compute, vector, arbiter, scratchpad, and counters | [rtl/attn_core.sv](../../rtl/attn_core.sv) |
| Compute datapath | `compute_engine` replaces the old fixed-latency stub and drives a real scratchpad-backed MAC flow | [rtl/compute_engine.sv](../../rtl/compute_engine.sv), [rtl/mac_array.sv](../../rtl/mac_array.sv) |
| DMA behavior | Host <-> scratchpad transfers now exercise both load and store paths with correct scratchpad read timing | [rtl/dma_engine.sv](../../rtl/dma_engine.sv), [sim/test_dma_engine.py](../../sim/test_dma_engine.py) |
| Vector path | Row-wise softmax now matches the 4 KiB slot model by consuming INT8 score tiles and emitting fixed-point INT8 weights | [rtl/vector_unit.sv](../../rtl/vector_unit.sv), [sim/test_vector_unit.py](../../sim/test_vector_unit.py) |
| Scratchpad | 8-bank scratchpad remains behavioral, but each bank now sits behind a dedicated `scratchpad_bank_1rw` wrapper for future SRAM replacement | [rtl/scratchpad.sv](../../rtl/scratchpad.sv), [rtl/scratchpad_bank_1rw.sv](../../rtl/scratchpad_bank_1rw.sv) |
| Golden models | Float/quantized attention reference plus RTL-oriented scoreboard helpers exist | [sim/reference_attention.py](../../sim/reference_attention.py), [sim/rtl_scoreboard.py](../../sim/rtl_scoreboard.py) |
| Verification evidence | Cocotb unit + integration suite passes `29` tests locally | [sim/](../../sim/) |
| Formal setup | Local `cvc4`-backed proofs now pass for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`; CI installs `cvc4` and invokes `make formal` | [formal/](../../formal/), [Makefile](../../Makefile), [.github/workflows/test.yml](../../.github/workflows/test.yml) |
| FPGA/front-end synthesis | `attn_core` is now the default synthesis top, `make fpga-elab` reproduces the hierarchy smoke artifact, and a dated backend smoke report captures the current front-end inventory plus heavier-flow blockers | [Makefile](../../Makefile), [fpga/README.md](../../fpga/README.md), [2026-03-15 Backend Smoke](reports/2026-03-15-backend-smoke.md) |
| ASIC flow | OpenLane now targets `attn_core`, uses an explicit SDC, and sees the scratchpad through bank wrappers | [openlane/config.json](../../openlane/config.json), [openlane/attn_core.sdc](../../openlane/attn_core.sdc) |

## What is still missing relative to the target program

- No end-to-end Q/K/V attention sequence in the integrated top yet; the de-risked hardware baseline currently validates the first `MATMUL -> SOFTMAX` half of the pipeline plus store-back.
- No OpenRAM configuration, generated SRAM macros, LEF/lib timing views, or macro integration collateral beyond the new wrapper boundary.
- No Caravel-specific wrappers, Wishbone bridge, logic-analyzer hookups, or user-project integration collateral.
- No software runtime, firmware driver, or compiler lowering pipeline in [software/](../../software/) and [compiler/](../../compiler/).
- No board-specific FPGA wrapper or constraints beyond the retargeted synthesis smoke flow.
- No unbounded liveness proof flow exists yet because SymbiYosys is still absent locally; the current DMA proof is a bounded safety run that constrains accepted valid commands to small transfers so the 6-step BMC depth stays tractable.

## Available command set

- `make doctor` validates the environment baseline.
- `make lint` checks the full RTL set with Verilator.
- `make test` runs the full cocotb regression suite.
- `make formal` runs the bounded `cvc4`-backed proof suite for the current formal harness set.
- `make sim` now defaults to the integrated `attn_core` top.
- `make fpga-elab` runs the lightweight Yosys hierarchy / inventory smoke flow for `attn_core`.
- `make fpga ICE40_ARCH=... ICE40_PACKAGE=...` targets the integrated top for the existing iCE40 flow.
- `make gds PDK_ROOT=$PDK_ROOT` launches OpenLane against the `attn_core` configuration.

## Planning implications

- The highest-risk integration gaps from the earlier audit are closed enough to support real block-to-block debugging rather than placeholder orchestration.
- The next major engineering step is broadening the integrated datapath from score-generation + softmax to full attention sequencing and software/runtime co-design.
- Backend work can now proceed against a realistic top-level netlist boundary, but area/timing numbers will remain distorted until the scratchpad wrapper is swapped to real SRAM macros.

## Reference reports

- [2026-03-15 Baseline Repo Audit](reports/2026-03-15-baseline-repo-audit.md)
- [2026-03-15 Architecture Study](reports/2026-03-15-architecture-study.md)
- [2026-03-15 Verification Plan](reports/2026-03-15-verification-plan.md)
- [2026-03-15 Verification Matrix](reports/2026-03-15-verification-matrix.md)
- [2026-03-15 System Integration](reports/2026-03-15-system-integration.md)
- [2026-03-15 Formal Verification](reports/2026-03-15-formal-verification.md)
- [2026-03-15 ASIC De-risking Update](reports/2026-03-15-asic-de-risking-update.md)
- [2026-03-15 Backend Smoke](reports/2026-03-15-backend-smoke.md)
