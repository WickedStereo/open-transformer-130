# Backend Smoke Report

Date: 2026-03-15
Sprints: 08A, 11A

## Summary

The integrated `attn_core` top now has a repeatable front-end backend smoke path via `make fpga-elab`. In the current container shell, that flow completes successfully, emits `build/fpga/attn_core_hierarchy.json`, and produces a usable Yosys hierarchy/stat inventory for the top-level design.

The heavier backend entrypoints are not yet equally repeatable in this shell:

- `make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48` was started as an iCE40 smoke run, but it did not return a timely result while still inside Yosys `synth_ice40` mapping for the integrated top.
- `make gds` was not runnable because Docker was inaccessible from the current shell, even though `PDK_ROOT=/pdk` and Sky130 PDK content was present.

## Commands exercised

### FPGA front-end smoke

Command:

```bash
make fpga-elab
```

Observed result:

- Pass
- Output artifact: `build/fpga/attn_core_hierarchy.json`
- Artifact size at capture time: about `2.7M`

Top-level hierarchy summary from Yosys:

- design hierarchy rooted at `attn_core`
- `13` memories / `1,115,472` memory bits
- `1,476` total cells
- `263` multiply cells
- `125` memory-read cells
- `113` memory-write cells

Notable instantiated subsystems in the hierarchy:

- `compute_engine` with one `mac_array` instance and `16` `mac_lane` instances
- `scratchpad` with `8` `scratchpad_bank_1rw` instances
- `dma_engine`, `vector_unit`, `tile_scheduler`, `isa_decoder`, `queue_ctrl`, `mmio_regs`, `perf_counters`, and `bank_arbiter`

### Full iCE40 smoke path

Command:

```bash
make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48
```

Observed result:

- Not adopted as a stable smoke gate yet
- The run was still inside `yosys synth_ice40` mapping after several minutes and did not produce timely smoke evidence for this session
- This is consistent with `attn_core` now being large enough that board/package PnR is a worse early checkpoint than pure hierarchy/elaboration

## OpenLane environment check

Environment facts observed in this shell:

- `PDK_ROOT=/pdk`
- `/pdk/sky130A` present
- Docker access unavailable from the current shell

Command:

```bash
make gds PDK_ROOT=$PDK_ROOT
```

Observed result:

- Immediate failure
- Error text: `Docker is not accessible from this shell.`

Implication:

- `11A` can proceed on configuration and reporting work, but a real `make gds` run is blocked until Docker access is restored in the devcontainer shell

## Interpretation

- `08A` now has a practical, fast, repeatable entrypoint that proves the integrated top elaborates and yields a concrete hierarchy artifact
- The repo should treat `make fpga-elab` as the first backend smoke gate, with full `make fpga` still considered heavier exploratory evidence
- `11A` remains partially blocked by environment setup rather than RTL parse/elaboration issues

## Immediate next actions

1. Keep `make fpga-elab` as the default front-end synthesis checkpoint for the integrated top.
2. Restore Docker accessibility in the devcontainer shell so `make gds` can collect real OpenLane evidence.
3. Revisit full iCE40 `make fpga` only after deciding whether a board-specific wrapper or a lighter synthesis-only FPGA metric is the intended `08A` gate.
