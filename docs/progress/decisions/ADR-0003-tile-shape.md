# ADR-0003 - 64x64 Baseline Tile Shape

Date: 2026-03-15
Status: accepted

## Context

The tiled execution model requires a fixed tile shape for scratchpad layout, DMA transfer sizing, scheduler design, and performance modeling. The master plan proposed 64x64 as a candidate, pending architecture study results.

## Decision

Adopt **64x64** as the baseline tile shape for the first architecture freeze.

- `tile_m = 64`, `tile_n = 64` for score (Q @ K^T) and value (weights @ V) phases.
- `tile_k` follows `d_model` and uses the same 64-element default.
- Tile dimensions are software-configurable via the `TILE_DEFAULT_M/N/K` MMIO registers and per-descriptor `dim_m/n/k` fields, allowing smaller tiles for non-square or boundary cases.

## Rationale

The performance model sweep (`sim/performance_model.py`) evaluated tiles from 8x8 to 128x128:

| Tile | MAC Utilization | Tiles in 128 KiB | Double-buffer feasible |
| --- | --- | --- | --- |
| 8x8 | 85.4% | 2048 | yes |
| 16x16 | 92.3% | 512 | yes |
| 32x32 | 95.5% | 128 | yes |
| **64x64** | **96.9%** | **32** | **yes** |
| 128x128 | 97.6% | 8 | yes (marginal) |

Key observations:

- 64x64 achieves 96.9% MAC utilization, within 0.7% of the larger 128x128 tile.
- 32 tiles fit in the 128 KiB scratchpad, comfortably supporting double-buffering with Q, K, V, and output tiles (4 tiles minimum).
- 128x128 tiles fit only 8 slots, leaving almost no room for prefetch buffering beyond the minimum working set.
- The bottleneck is compute-bound at all tile sizes, meaning the memory subsystem keeps up. This validates the 128 KiB scratchpad target.
- Scheduler overhead drops from 4096 cycles (8x8) to 64 cycles (64x64), a 64x reduction.

## Alternatives Considered

- **32x32**: 95.5% utilization is close but wastes 4x more scheduler cycles. Viable fallback if area constraints force a smaller scratchpad.
- **128x128**: Marginally better utilization but too tight on scratchpad slots for safe double-buffering. Rejected as default, but supported via per-descriptor overrides.
- **Non-square tiles (e.g. 64x32)**: Add complexity to the scheduler and MAC array for minimal benefit. Rejected for baseline; the descriptor format supports non-square shapes for boundary handling.

## Consequences

- The scratchpad must accommodate at least 4 tiles of 64x64x1 = 4 KiB each (16 KiB minimum). The 128 KiB target provides 32 slots, ample for prefetch and double-buffering.
- DMA transfers are 4 KiB per tile load/store -- well-aligned for burst-mode transfers.
- The MAC array width (16 lanes) processes one row of a 64-wide tile in 4 cycles, which is efficient.
- Performance model outputs at 64x64 become the reference baseline for later RTL and FPGA comparisons.

## Follow-Up

- [sim/reference_attention.py](../../../sim/reference_attention.py): `TileConfig(64, 64)` is the default.
- [sim/performance_model.py](../../../sim/performance_model.py): sweep data validates this choice.
- Sprint 02 microarchitecture must size scratchpad banks and DMA burst length for 64x64 tiles.
- Sprint 04 memory subsystem RTL must handle 4 KiB aligned transfers.
