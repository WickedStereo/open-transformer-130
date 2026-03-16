# Current Repository State

Date: 2026-03-16
Status: integrated prototype / non-ASIC closure baseline

## Executive summary

The repository now contains a real integrated `attn_core` baseline rather than a placeholder-only top. The current implementation supports the full currently-scoped single-tile attention fragment over INT8 tiles:

`LOAD_TILE(Q) -> LOAD_TILE(K^T) -> MATMUL(score) -> SOFTMAX(weights) -> LOAD_TILE(V) -> MATMUL(output) -> STORE_TILE`

That flow is exercised through RTL integration tests, software/runtime helpers, compiler lowering utilities, and the FPGA demo wrapper.

The verification baseline is materially stronger than before:

- `make lint` passes.
- `make test` passes `36` Python and cocotb regressions.
- `make formal` passes with bounded `cvc4` proofs for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`.
- `make fpga-elab`, `make fpga-demo-elab`, and `make fpga-demo` pass locally; the compact iCEBreaker build routes at `2648 / 5280` LCs (50%) and clears the `12 MHz` target at `20.10 MHz`.
- The repo now includes standalone benches for `queue_ctrl`, `dma_engine`, `vector_unit`, `tile_scheduler`, `perf_counters`, `compute_engine`, the full `attn_core` Q/K/V flow, the FPGA demo wrapper, the runtime layer, and the compiler/lowering path.
- Formal harnesses are attached under `formal/` for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`, and the current bounded suite is green in both local runs and CI.

The repo is still not tapeout-ready, but that is now a deliberate scope boundary rather than missing near-term project work. The current push intentionally excludes ASIC-implementation sprints such as SRAM macro integration, Caravel packaging, physical design, tapeout, and post-silicon validation.

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
| System-level attention flow | Integrated RTL now executes the current full single-tile Q/K/V attention sequence and stores the final output back to host memory | [rtl/attn_core.sv](../../rtl/attn_core.sv), [sim/test_attn_core.py](../../sim/test_attn_core.py), [compiler/lowering.py](../../compiler/lowering.py) |
| Software runtime | Thin host runtime can pack descriptors, stage queue/tile memory, program MMIO, wait for completion, and read results | [software/runtime.py](../../software/runtime.py), [software/test_runtime.py](../../software/test_runtime.py) |
| Compiler/lowering | Attention lowering helpers generate the supported descriptor sequence, compute goldens, and extract a minimal ONNX attention pattern | [compiler/lowering.py](../../compiler/lowering.py), [compiler/onnx_to_tile.py](../../compiler/onnx_to_tile.py), [compiler/test_lowering.py](../../compiler/test_lowering.py) |
| Verification evidence | Python + cocotb unit and integration suite passes `36` tests locally | [sim/](../../sim/), [software/](../../software/), [compiler/](../../compiler/) |
| Formal setup | Bounded `cvc4`-backed proofs pass for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`; the scheduler closure uses a reduced 4-slot harness to keep the bounded safety run tractable | [formal/](../../formal/), [Makefile](../../Makefile), [.github/workflows/test.yml](../../.github/workflows/test.yml) |
| FPGA/front-end synthesis | `attn_core` remains the default synthesis top, `make fpga-elab` reproduces the hierarchy smoke artifact, and the compact iCEBreaker demo now elaborates, places/routes on UP5K, and emits `icebreaker_demo_top.bin` | [Makefile](../../Makefile), [fpga/README.md](../../fpga/README.md), [fpga/fpga_attention_demo.sv](../../fpga/fpga_attention_demo.sv), [fpga/icebreaker_demo_top.sv](../../fpga/icebreaker_demo_top.sv) |

## What is still missing relative to the target program

- The integrated workload is still the current single-tile attention fragment; there is no multi-tile scheduler/runtime flow, batching, or full transformer-layer orchestration yet.
- ONNX lowering only supports a narrow rank-2 `MatMul -> Softmax -> MatMul` pattern and should be treated as a bring-up path, not a general compiler.
- The FPGA demo intentionally uses a compact directed wrapper with precomputed softmax weights plus the behavioral scratchpad path, so board-level area/timing evidence is demonstrative rather than a general FPGA deployment of the full `attn_core`.
- No unbounded liveness proof flow exists yet because SymbiYosys is still absent locally; the current DMA and scheduler proofs remain bounded safety runs.
- ASIC-specific implementation work such as SRAM macros, Caravel integration, physical design, tapeout prep, and post-silicon validation is intentionally deferred for the current scope.

## Available command set

- `make doctor` validates the environment baseline.
- `make lint` checks the full RTL set with Verilator.
- `make test` runs the full cocotb regression suite.
- `make formal` runs the bounded `cvc4`-backed proof suite for the current formal harness set.
- `make sim` now defaults to the integrated `attn_core` top.
- `make fpga-elab` runs the lightweight Yosys hierarchy / inventory smoke flow for `attn_core`.
- `make fpga ICE40_ARCH=... ICE40_PACKAGE=...` targets the integrated top for the existing iCE40 flow.
- `make fpga-demo-elab` runs the fast iCEBreaker wrapper elaboration flow.
- `make fpga-demo` launches the full iCEBreaker bitstream build.

## Planning implications

- The highest-risk integration gaps from the earlier audit are closed enough to support real hardware/software co-design rather than placeholder orchestration.
- The next major non-ASIC steps are broadening model coverage, keeping the bounded formal suite green as the RTL evolves, and deciding whether future FPGA work justifies BRAM-specialized cleanup.
- ASIC follow-on work can resume later against a more credible top-level contract, but it is intentionally not the current execution target.

## Reference reports

- [2026-03-15 Baseline Repo Audit](reports/2026-03-15-baseline-repo-audit.md)
- [2026-03-15 Architecture Study](reports/2026-03-15-architecture-study.md)
- [2026-03-15 Verification Plan](reports/2026-03-15-verification-plan.md)
- [2026-03-15 Verification Matrix](reports/2026-03-15-verification-matrix.md)
- [2026-03-15 System Integration](reports/2026-03-15-system-integration.md)
- [2026-03-15 Formal Verification](reports/2026-03-15-formal-verification.md)
- [2026-03-16 Non-ASIC Closeout](reports/2026-03-16-non-asic-closeout.md)
- [2026-03-15 ASIC De-risking Update](reports/2026-03-15-asic-de-risking-update.md)
- [2026-03-15 Backend Smoke](reports/2026-03-15-backend-smoke.md)
