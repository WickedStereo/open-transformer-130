# 2026-03-15 ASIC De-risking Update

## Summary

This update converts the repository from a review-stage prototype with major documentation drift into a de-risked integrated baseline that exercises a real `LOAD_TILE -> MATMUL -> SOFTMAX -> STORE_TILE` path.

The work focused on five areas:

1. Aligning status documentation with the actual repo contents.
2. Fixing the highest-risk DMA and scratchpad protocol mismatches.
3. Replacing the top-level compute stub with a real scratchpad-backed compute engine.
4. Upgrading verification from plan-only collateral to runnable benches and formal harnesses.
5. Retargeting FPGA/OpenLane collateral from `attention_stub` to `attn_core`.

## Code changes

### Integrated datapath

- Added [`rtl/compute_engine.sv`](../../../rtl/compute_engine.sv) as a real compute backend for `attn_core`.
- `compute_engine` prefetches source tiles from scratchpad, drives [`rtl/mac_array.sv`](../../../rtl/mac_array.sv), and writes INT8 outputs back to scratchpad.
- [`rtl/attn_core.sv`](../../../rtl/attn_core.sv) now instantiates `compute_engine` instead of using the earlier fixed-latency compute timer.

### Memory protocol fixes

- Reworked [`rtl/dma_engine.sv`](../../../rtl/dma_engine.sv) so:
  - load commands actually issue host-bus reads,
  - store commands respect the 1-cycle scratchpad read latency,
  - invalid transfer sizes raise `error`,
  - `bytes_moved` reports true transfer size.
- Reworked [`rtl/vector_unit.sv`](../../../rtl/vector_unit.sv) to consume INT8 score tiles directly, matching the 4 KiB slot model.
- Added [`rtl/scratchpad_bank_1rw.sv`](../../../rtl/scratchpad_bank_1rw.sv) and moved scratchpad banks behind that wrapper in [`rtl/scratchpad.sv`](../../../rtl/scratchpad.sv).

### Scheduler / programming model closure

- [`rtl/tile_scheduler.sv`](../../../rtl/tile_scheduler.sv) now derives DMA host addresses as `DMA_HOST_ADDR + slot_id * 4096`, which makes queued multi-tile DMA sequences practical with a single base register.
- The current integrated compute contract is intentionally in-place for `MATMUL`: the RHS tile is prefetched, then overwritten with the result tile.

## Verification evidence

### Cocotb

Local regression after the update:

- `make lint`: pass
- `make test`: `29 passed`

New standalone benches added:

- [`sim/test_queue_ctrl.py`](../../../sim/test_queue_ctrl.py)
- [`sim/test_dma_engine.py`](../../../sim/test_dma_engine.py)
- [`sim/test_vector_unit.py`](../../../sim/test_vector_unit.py)
- [`sim/test_tile_scheduler.py`](../../../sim/test_tile_scheduler.py)
- [`sim/test_perf_counters.py`](../../../sim/test_perf_counters.py)
- [`sim/test_compute_engine.py`](../../../sim/test_compute_engine.py)

New integration evidence:

- [`sim/test_attn_core.py`](../../../sim/test_attn_core.py) now includes an end-to-end scoreboard-based `LOAD -> MATMUL -> SOFTMAX -> STORE` regression.
- [`sim/rtl_scoreboard.py`](../../../sim/rtl_scoreboard.py) provides hardware-matching fixed-point references for the integrated datapath.

### Formal

- Added harness modules:
  - [`formal/mac_lane_formal.sv`](../../../formal/mac_lane_formal.sv)
  - [`formal/isa_decoder_formal.sv`](../../../formal/isa_decoder_formal.sv)
  - [`formal/dma_engine_formal.sv`](../../../formal/dma_engine_formal.sv)
  - [`formal/tile_scheduler_formal.sv`](../../../formal/tile_scheduler_formal.sv)
- Updated the `.sby` files to target those harnesses.
- Added `make formal` and a CI workflow step to run it.
- In the current local environment, SMT2 generation succeeds, but end-to-end proof runs were not executed because the SMT solver binary is not installed.

## Backend / FPGA collateral

- [`openlane/config.json`](../../../openlane/config.json) now targets `attn_core`.
- Added [`openlane/attn_core.sdc`](../../../openlane/attn_core.sdc).
- [`Makefile`](../../../Makefile) now defaults `TOP` to `attn_core`.
- The RTL now elaborates successfully through the repo's Yosys front-end into [`build/fpga/attn_core_hierarchy.json`](../../../build/fpga/attn_core_hierarchy.json).

## Remaining risks

- The integrated top still implements only the score-generation + softmax half of attention; a full value-phase integration remains future work.
- Scratchpad wrappers exist, but there are still no real SRAM macros or timing views behind them.
- The formal flow is wired in, but proof results still need to be collected in an environment with the solver installed.
- Board-specific FPGA collateral and Caravel integration are still absent.
