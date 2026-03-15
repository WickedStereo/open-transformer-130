# Memory Hierarchy

## Hierarchy overview

The hierarchy is intentionally software-managed:

`Host memory -> DMA engine -> scratchpad SRAM -> compute units -> scratchpad SRAM -> DMA engine -> host memory`

This reduces the complexity of coherence and cache behavior while making data movement visible to both the performance model and the verification plan.

## Frozen scratchpad parameters (Sprint 01)

| Parameter | Value | Decision |
| --- | --- | --- |
| Capacity | 128 KiB (131,072 bytes) | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Banks | 8 banks of 16 KiB | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Tile slots | 32 addressable slots of 4 KiB | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Addressing | `byte_addr = tile_slot_id * 4096 + offset` | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Bank mapping | `bank = byte_addr[16:14]`, `bank_offset = byte_addr[13:0]` | implemented baseline |
| Port model | Single-port per bank, priority DMA > MAC > vector | [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md) |
| Implementation | Behavioral banks behind `scratchpad_bank_1rw` wrappers | implemented baseline |

## DMA responsibilities

- Fetch tiles from host-visible memory into scratchpad slots.
- Store scratchpad tiles back to host-visible memory.
- Accept byte counts up to 4096 and split them into 16-byte host bursts plus serialized scratchpad accesses.
- Reject zero-length or oversize transfers.
- Expose byte counters via `PERF_DMA_BYTES` MMIO register.
- Signal completion to the scheduler for dependency tracking.

### Current queued-DMA addressing profile

The integrated scheduler currently derives host addresses as:

`effective_host_addr = DMA_HOST_ADDR + slot_id * 4096`

That keeps the queued command format compact while still allowing multi-tile command sequences to target distinct host-memory regions.

## Double-buffering model

The performance model validates that 32 tile slots comfortably support double-buffering:
- 4 active tiles minimum (Q, K, V, output).
- 28 slots available for prefetch and tile reuse.
- At 64x64 tiles, compute is the bottleneck -- the DMA subsystem keeps up.

## Open design questions (carried to Sprint 02)

- Bank arbiter backpressure contract: stall vs. retry semantics.
- DMA burst alignment requirements for Wishbone/Caravel bus.
- OpenRAM macro selection and area estimation for SKY130.

The softmax-temporary question is now resolved for the integrated baseline: the vector unit keeps `row_max`, `row_sum`, and `exp_buf` locally rather than spilling them to scratchpad.

## Verification hooks

- Scoreboard for host-memory to scratchpad data integrity.
- Assertions for no out-of-range bank access.
- Backpressure tests across DMA and scheduler boundaries.
- Reportable counters for bytes moved, bank conflicts, and idle cycles.
