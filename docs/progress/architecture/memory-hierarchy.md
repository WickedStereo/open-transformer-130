# Memory Hierarchy

## Hierarchy overview

The planned hierarchy is intentionally software-managed:

`Host memory -> DMA engine -> scratchpad SRAM -> compute units -> scratchpad SRAM -> DMA engine -> host memory`

This reduces the complexity of coherence and cache behavior while making data movement visible to both the performance model and the verification plan.

## Frozen scratchpad parameters (Sprint 01)

| Parameter | Value | Decision |
| --- | --- | --- |
| Capacity | 128 KiB (131,072 bytes) | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Banks | 8 banks of 16 KiB | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Tile slots | 32 addressable slots of 4 KiB | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Addressing | `byte_addr = tile_slot_id * 4096 + offset` | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Bank mapping | Interleaved at 16 KiB boundaries | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Port model | Single-port per bank, priority DMA > MAC > vector | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Implementation | Behavioral SRAM initially, OpenRAM macros for ASIC | planned |

## DMA responsibilities

- Fetch tiles from host-visible memory into scratchpad slots.
- Handle aligned 4 KiB burst transfers (one tile per burst).
- Enforce bounds: reject tile slot IDs >= 32.
- Expose byte counters via `PERF_DMA_BYTES` MMIO register.
- Signal completion to the scheduler for dependency tracking.

## Double-buffering model

The performance model validates that 32 tile slots comfortably support double-buffering:
- 4 active tiles minimum (Q, K, V, output).
- 28 slots available for prefetch and tile reuse.
- At 64x64 tiles, compute is the bottleneck -- the DMA subsystem keeps up.

## Open design questions (carried to Sprint 02)

- Bank arbiter backpressure contract: stall vs. retry semantics.
- Softmax temporaries: scratchpad vs. local line buffers in vector unit.
- DMA burst alignment requirements for Wishbone/Caravel bus.
- OpenRAM macro selection and area estimation for SKY130.

## Verification hooks

- Scoreboard for host-memory to scratchpad data integrity.
- Assertions for no out-of-range bank access.
- Backpressure tests across DMA and scheduler boundaries.
- Reportable counters for bytes moved, bank conflicts, and idle cycles.
