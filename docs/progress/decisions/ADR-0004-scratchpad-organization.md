# ADR-0004 - 128 KiB Banked Scratchpad with Software-Managed Tile Slots

Date: 2026-03-15
Status: accepted

## Context

The memory hierarchy must balance capacity, bank count, and port arbitration complexity. The master plan proposed a 128 KiB class scratchpad with banked organization, pending architecture study and tile-shape decisions.

## Decision

Adopt a **128 KiB, 8-bank scratchpad with 32 software-visible tile slots**.

- Total capacity: 131,072 bytes (128 KiB).
- Bank count: 8 banks of 16 KiB each.
- Tile slots: 32 addressable slots of 4 KiB each (matching 64x64 INT8 tiles).
- Addressing: `byte_addr = tile_slot_id * 4096 + offset`.
- Bank mapping: interleaved at 16 KiB boundaries (`bank = byte_addr / 16384`).
- Port model: single-port per bank with arbitration priority DMA > MAC > vector.

## Rationale

With the 64x64 tile shape (ADR-0003) and INT8 operands (ADR-0002):

- Each tile occupies 4 KiB.
- 32 tile slots provide room for double-buffering: 4 active tiles (Q, K, V, output) plus 28 prefetch/reuse slots.
- 8 banks allow 2 tiles per bank, reducing bank-conflict probability when DMA and compute access different tiles concurrently.
- The performance model shows the system is compute-bound, so the memory subsystem does not need aggressive bank parallelism -- 8 banks provide sufficient conflict avoidance.

The scratchpad model in `sim/reference_attention.py` (`ScratchpadModel`) validates:
- `tiles_that_fit(TileConfig(64, 64))` returns 32.
- `double_buffer_feasible(TileConfig(64, 64), tiles_needed=4)` returns True.

## Alternatives Considered

- **64 KiB scratchpad**: Only 16 tile slots, leaving just 12 for prefetch. Marginal for longer sequences with many K/V tiles. Rejected for baseline.
- **256 KiB scratchpad**: Generous headroom but may not fit within SKY130 area budget for the Caravel user project area. Rejected for first tapeout.
- **16 banks**: Reduces conflict probability further but doubles address-decode and arbitration logic. Rejected as over-provisioned for a compute-bound design.
- **Cache-based hierarchy**: Coherence logic and replacement policies add substantial complexity. Rejected in favor of software-managed simplicity.

## Consequences

- The DMA engine and tile scheduler use slot IDs 0-31 directly.
- Software must manage tile residency explicitly -- no hardware replacement policy.
- The ISA's `LOAD_TILE` and `STORE_TILE` commands address scratchpad by tile slot ID.
- Bank conflicts are possible when DMA and compute target the same bank; the arbitration priority (DMA > MAC > vector) ensures forward progress.
- Implementation will start with behavioral SRAM in RTL and transition to OpenRAM macros for ASIC.

## Follow-Up

- [sim/reference_attention.py](../../../sim/reference_attention.py): `ScratchpadModel` encodes this decision.
- Sprint 02 must specify the bank arbiter interface and backpressure contract.
- Sprint 04 memory subsystem RTL implements the banked scratchpad.
- Sprint 11 physical design must provision area for 128 KiB of SRAM (OpenRAM macros on SKY130).
