# Non-ASIC Closeout Report

Date: 2026-03-16
Sprints: 06, 07, 08, 09

## Summary

The repository now closes the originally missing non-ASIC workstreams around end-to-end single-tile attention execution, host/runtime control, compiler lowering, and board-oriented FPGA demo collateral.

The most important change is that the project no longer stops at an RTL-only score-path checkpoint. The current baseline includes:

- a full single-tile Q/K/V attention command sequence through `attn_core`
- a reusable Python runtime for descriptor packing, queue staging, execution, and result collection
- compiler-side lowering helpers plus minimal ONNX attention-pattern extraction
- an iCEBreaker-oriented demo wrapper and board top with simulation coverage

## Evidence summary

| Command | Result | Notes |
| --- | --- | --- |
| `make lint` | Passed | Verilator lint clean on the RTL set |
| `make test` | Passed | `36 passed in 9.66s` across `sim`, `software`, and `compiler` |
| `make fpga-elab` | Passed | Existing `attn_core` hierarchy smoke remains usable |
| `make fpga-demo-elab` | Passed | The compact iCEBreaker wrapper elaborates quickly and stays usable as a frontend smoke check |
| `make formal` / `make formal-tile-scheduler` | Passed | Bounded `cvc4` proofs now close for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`; the scheduler harness uses a reduced 4-slot model at `-t 10` |
| `make fpga-demo` | Passed | The compact UP5K demo routes at `2648 / 5280` LCs (50%), clears the `12 MHz` target at `20.10 MHz`, and `icepack` emits `build/fpga/icebreaker_demo_top.bin` |

## Sprint-by-sprint impact

### Sprint 07

System integration now covers the currently supported end-to-end attention fragment instead of only the earlier score-generation path. The integrated cocotb flow uses the same lowering helpers that the software/compiler path uses, so the RTL and software stacks now agree on the descriptor sequence.

### Sprint 08

The repo now has a concrete FPGA demo lane:

- `fpga/fpga_attention_demo.sv` provides a self-contained compact attention workload harness built directly from `compute_engine` plus the scratchpad path
- `fpga/icebreaker_demo_top.sv` maps the demo to iCEBreaker clock, button, and LED I/O
- `fpga/icebreaker_demo.pcf` captures the board constraints
- `sim/test_fpga_attention_demo.py` verifies that the directed workload completes and stores the expected output

The main tooling and architecture change in this sprint was replacing the oversized full-stack board path with a compact directed demo that preloads fixed tiles locally and writes precomputed softmax weights for the supported workload. That keeps `make fpga-demo-elab` fast, lets the design fit the iCE40UP5K, and still exercises the compute/scratchpad dataflow with board-visible status LEDs.

The resulting board-build evidence is now concrete rather than aspirational: `make fpga-demo` places and routes the wrapper at `2648 / 5280` logic cells (50%), uses `4 / 30` RAMs, clears timing at `20.10 MHz` for the `12 MHz` board clock, and produces `build/fpga/icebreaker_demo_top.bin`.

### Sprint 09

The thin-runtime and lowering baseline is now implemented:

- `software/runtime.py` exposes descriptor, host-memory, and MMIO/runtime abstractions
- `compiler/lowering.py` emits the supported attention descriptor sequence and goldens
- `compiler/onnx_to_tile.py` finds a minimal supported ONNX attention pattern and lowers it into the same command plan

This is enough to treat software/compiler bring-up as real project infrastructure rather than a future placeholder.

### Sprint 06

Formal infrastructure is no longer placeholder-only. `make formal` now passes end to end with `cvc4` across `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`. The scheduler closure came from aligning the properties with sequential slot-state updates, shrinking the harness to a 4-slot model for tractability, constraining valid opcodes, and explicitly checking busy / issue / completion sequencing instead of assuming combinational behavior that the RTL does not provide.

## Remaining non-ASIC follow-on items

- Extend the software/compiler path beyond the current single-tile attention fragment and narrow ONNX pattern.
- Expand the bounded formal lane only if needed for future scope, for example with deeper DMA bounds or unbounded/SymbiYosys-backed liveness work.
- Consider BRAM-specialized scratchpad adaptation if later FPGA work needs better area/timing than the current behavioral board path provides.
