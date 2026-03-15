# Physical Awareness Notes

Status: spec frozen (Sprint 02)

## Purpose

Record area, timing, clocking, and reset assumptions early so that RTL authors make informed trade-offs and physical-design surprises are minimized.

## Area estimates

### Block-level area dominance

| Block | Area driver | Rough estimate | Notes |
| --- | --- | --- | --- |
| Scratchpad SRAM | 128 KiB storage | ~3.5-4.5 mm^2 | Dominates total area. OpenRAM macros on SKY130. |
| MAC array | 16 x (8x8 multiplier + 32-bit accumulator) | ~0.3-0.5 mm^2 | Multiplier area depends on synthesis tool optimization. |
| Vector/softmax unit | Exp LUT (32 entries) + register file (136 bytes) + reduction trees | ~0.05-0.1 mm^2 | Small relative to SRAM and MAC. |
| Control plane | Decoder + queue controller + scheduler FSM + MMIO regs | ~0.02-0.05 mm^2 | Minimal combinational + state logic. |
| Bank arbiter | 8 x 3-input priority muxes | ~0.01 mm^2 | Trivial. |
| DMA engine | FSM + address generators + counters | ~0.02-0.05 mm^2 | Modest. |
| Debug/counters | 4 x 32-bit saturating counters + probe mux | ~0.01 mm^2 | Trivial. |

**Total estimate**: ~4-5 mm^2, dominated by SRAM. The Caravel user project area is approximately 10 mm^2 on SKY130, so the design should fit with margin.

### Area sensitivity parameters

These are the two parameters most likely to require adjustment after synthesis:

1. **MAC lane count** (default 16): reducing to 8 halves MAC array area at the cost of 2x longer compute time per tile. Utilization impact is modest (performance model shows system is already compute-bound).
2. **Scratchpad capacity** (default 128 KiB): reducing to 64 KiB halves SRAM area but limits tile slots to 16 and tightens double-buffering margin.

## Clock domain

**Single clock domain** for all blocks.

| Parameter | Value | Rationale |
| --- | --- | --- |
| Clock name | `clk` | Single system clock |
| Target frequency | ~150 MHz | SKY130 planning target |
| Clock source | External (from Caravel harness or FPGA PLL) | No internal PLL |
| No clock gating | First implementation | Simplicity; power optimization deferred |

All inter-block interfaces are synchronous to `clk`. No CDC (clock-domain crossing) logic is needed.

## Reset

**Synchronous, active-low, single domain.**

| Parameter | Value | Rationale |
| --- | --- | --- |
| Reset name | `rst_n` | Active-low convention |
| Reset type | Synchronous | Avoids async reset timing complications on SKY130 |
| Reset scope | All blocks | Single reset tree |
| Soft reset | Via CTRL register bit[1] | Clears counters and state without full re-initialization |

Reset behavior per block:

| Block | On `rst_n` assertion | On soft reset (CTRL bit[1]) |
| --- | --- | --- |
| mac_lane | Clear accumulator, pipeline flush | Same |
| mac_array | Deassert tile_ready, clear busy | Same |
| scratchpad | Contents undefined (no clear) | Contents preserved |
| bank_arbiter | Clear all grants | Same |
| dma_engine | Abort transfer, clear state | Same |
| queue_ctrl | Reset tail to 0 | Reset tail to 0 |
| decoder | Clear fault state | Clear fault state |
| tile_scheduler | Enter IDLE, clear slot states | Enter IDLE, clear slot states |
| vector_unit | Clear pipeline, deassert busy | Same |
| mmio_regs | Load reset values per register | Clear counters only |
| debug_counters | Clear all counters | Clear all counters |

## Critical timing paths (pre-synthesis assessment)

| Path | From | To | Concern | Mitigation |
| --- | --- | --- | --- | --- |
| MAC multiply-accumulate | `op_a/op_b` registers | `accum_out` register | 8x8 signed multiply + 32-bit add + saturation check | 3-stage pipeline absorbs this |
| Scratchpad bank access | `bank_addr` | `rdata` | Single-port SRAM read latency | 1-cycle read latency budgeted |
| Arbiter priority resolve | 3x `req` signals | `grant` output | 3-input priority logic per bank x 8 banks | Pure combinational, small fan-in |
| Decoder fault check | `desc_data` | `fault_valid` | 3-way priority fault detection on 64-bit descriptor | 1-cycle pipeline for fault detection |
| Writeback backpressure | `result_ready` from arbiter | `mac_array` stall | Combinational loop risk | Register the ready signal |

## Floorplan pressure points

1. **SRAM placement**: 8 OpenRAM macros (16 KiB each) dominate the floorplan. Place in a regular 2x4 or 4x2 grid near the MAC array to minimize data routing.
2. **MAC array routing**: 16 lanes with 128-bit operand buses fan out from scratchpad banks. Place MAC array adjacent to SRAM.
3. **DMA bus interface**: host-bus signals route to the chip boundary (Caravel pads). Place DMA near I/O.
4. **Clock tree**: single domain simplifies clock tree synthesis. No special buffering needed.

## Implementation flexibility

| Decision | Flexibility | When it locks |
| --- | --- | --- |
| MAC lane count (8 or 16) | High -- parameterized in RTL | After Sprint 03 synthesis feedback |
| Scratchpad bank count (4 or 8) | Medium -- changes arbiter width | After Sprint 04 synthesis feedback |
| Scratchpad capacity (64 or 128 KiB) | Medium -- changes OpenRAM config | After Sprint 11 area assessment |
| Pipeline stages in MAC lane | Medium -- affects timing closure | After Sprint 03 timing analysis |
| Exp LUT size in vector unit | High -- 32 or 64 entries | After Sprint 05 accuracy study |
| Debug probe selection | High -- tap point list is configurable | Until Sprint 08 FPGA freeze |

## SKY130 technology notes

- Standard cells: `sky130_fd_sc_hd` (high density) for logic.
- SRAM: OpenRAM-generated macros. Compile-time parameters: word size, depth, port count.
- Metal stack: 5 metal layers. Scratchpad macros and power grid will compete for upper metals.
- Power: nominal 1.8V. No multi-voltage design planned for first tapeout.
- Process variation: digital corners (SS, TT, FF) must be covered in timing closure. Target frequency is for TT corner.
