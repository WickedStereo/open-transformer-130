# Backend Smoke Report

Date: 2026-03-15
Sprints: 08A, 11A

## Summary

The integrated `attn_core` top now has two repeatable Docker-independent backend smoke paths in the current container shell:

- `make fpga-elab` for the `08A` hierarchy/elaboration checkpoint
- `make asic-prep` for a pre-OpenLane `11A` checkpoint based on Yosys `prep`

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

### ASIC pre-OpenLane smoke

Command:

```bash
make asic-prep
```

Observed result:

- Pass
- Output artifact: `build/asic/attn_core_prep.json`
- Artifact size at capture time: about `3.3M`

Top-level generic-cell summary from Yosys `prep`:

- design hierarchy rooted at `attn_core`
- `4,174` total cells after process lowering / generic mapping prep
- `252` `$dff` cells
- `776` `$eq` cells
- `1,907` `$mux` cells
- `13` `$mem` cells
- `36` `$mul` cells

Largest integrated blocks in the `prep` inventory:

- `dma_engine`: `1,486` cells, dominated by `708` `$mux` and `439` `$pmux`
- `compute_engine`: `780` cells, with `235` `$mux`, `188` `$pmux`, and `10` `$mul`
- `vector_unit`: `538` cells, with `128` `$mux`, `185` `$pmux`, and `5` `$mul`
- `scratchpad`: `8` bank-wrapper cells above the per-bank memories

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
- `11A` now also has a Docker-independent `make asic-prep` checkpoint that lowers the design far enough to expose generic-cell pressure before a full OpenLane run
- The repo should treat `make fpga-elab` as the first backend smoke gate, with full `make fpga` still considered heavier exploratory evidence
- `11A` remains partially blocked by environment setup rather than RTL parse/elaboration issues

## Immediate next actions

1. Keep `make fpga-elab` as the default front-end synthesis checkpoint for the integrated top.
2. Keep `make asic-prep` as the default Docker-independent `11A` checkpoint until OpenLane is runnable in this shell.
3. Restore Docker accessibility in the devcontainer shell so `make gds` can collect real OpenLane evidence.
4. Revisit full iCE40 `make fpga` only after deciding whether a board-specific wrapper or a lighter synthesis-only FPGA metric is the intended `08A` gate.
