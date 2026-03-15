# Debug and Observability

Status: spec frozen (Sprint 02)

## Purpose

Debug infrastructure makes performance and correctness issues visible during simulation, FPGA prototyping, Caravel bring-up, and post-silicon validation. All debug features are designed into the datapath from Sprint 03 onward to avoid late retrofitting.

## Performance counter registers

Four 32-bit saturating counters are exposed through the MMIO register map:

| Register | Offset | Increments when | Saturates at |
| --- | --- | --- | --- |
| `PERF_BUSY_CYCLES` | 0x28 | Scheduler is not IDLE | 0xFFFFFFFF |
| `PERF_STALL_CYCLES` | 0x2C | Scheduler is waiting on DMA, arbiter, or backpressure | 0xFFFFFFFF |
| `PERF_DMA_BYTES` | 0x30 | DMA completes a 16-byte burst | 0xFFFFFFFF |
| `PERF_TILE_COUNT` | 0x34 | Scheduler completes a MATMUL or SOFTMAX tile | 0xFFFFFFFF |

### Counter implementation

```systemverilog
// Saturating increment: adds 1 unless already at max
always_ff @(posedge clk) begin
  if (!rst_n || soft_reset)
    counter <= 32'd0;
  else if (increment && counter != 32'hFFFFFFFF)
    counter <= counter + 32'd1;
end
```

Counters are:
- Cleared on `rst_n` assertion or `soft_reset` (CTRL bit[1]).
- Read via MMIO at any time without side effects.
- Free-running (no pause/resume control to avoid datapath perturbation).

## Status and fault registers

### `STATUS` register (offset 0x04, read-only)

| Bit | Name | Description |
| --- | --- | --- |
| 0 | `busy` | Scheduler has active or pending work |
| 1 | `fault` | Decoder detected a fault (halts queue) |
| 2 | `dma_active` | DMA transfer in progress |
| 3 | `compute_active` | MAC array processing a tile |
| 7:4 | `queue_depth` | Number of descriptors between tail and head |

### `FAULT_INFO` register (offset 0x18, read-only)

| Bit | Name | Description |
| --- | --- | --- |
| 1:0 | `cause` | 00=reserved_field, 01=invalid_opcode, 10=tile_oob |
| 9:2 | `faulting_opcode` | Opcode byte of faulting descriptor |
| 73:10 | `faulting_descriptor` | Full 64-bit faulting descriptor |

Cleared when software writes `fault_clear` (CTRL bit[2]).

## Probe point list

Probe points are internal signals exposed for debug visibility. Each probe is a named wire that can be sampled by cocotb, logic analyzers, or Caravel firmware.

| Probe | Width | Source block | Description |
| --- | --- | --- | --- |
| `sched_state` | 4 | tile_scheduler | Current scheduler FSM state |
| `sched_slot_state` | 64 | tile_scheduler | 32 x 2-bit tile residency bitmap |
| `dma_state` | 3 | dma_engine | DMA FSM state (idle/load/store/error) |
| `dma_slot_active` | 5 | dma_engine | Slot currently being transferred |
| `queue_occupancy` | 8 | queue_ctrl | Entries in queue (head - tail) |
| `mac_busy_lanes` | 16 | mac_array | Per-lane busy bitmap |
| `vec_stage` | 3 | vector_unit | Softmax pipeline stage |
| `arb_conflict` | 8 | bank_arbiter | Per-bank conflict bitmap this cycle |

## FPGA debug tap

For the FPGA prototype (Sprint 08), a subset of probes route to physical pins for logic analyzer capture.

### Tap selection register

A `DEBUG_SEL` configuration (set via `CONFIG` command or a dedicated MMIO register added in Sprint 08) selects which probe group appears on debug output pins:

| `DEBUG_SEL` | Probe group | Width |
| --- | --- | --- |
| 0 | `sched_state` + `dma_state` + `vec_stage` | 10 bits |
| 1 | `queue_occupancy` + `mac_busy_lanes[3:0]` | 12 bits |
| 2 | `arb_conflict` + `dma_slot_active` | 13 bits |
| 3 | `sched_slot_state[15:0]` | 16 bits |

### Pin budget

Target: 16 debug output pins on the FPGA board wrapper, directly observable with a logic analyzer or ILA core.

## Caravel mapping

For Caravel integration (Sprint 10), debug access is through firmware-readable registers rather than physical pins.

| Access method | Signals | Notes |
| --- | --- | --- |
| Wishbone register reads | All MMIO registers including STATUS, FAULT_INFO, PERF_* | Standard register model |
| Logic analyzer probes | Selected probe group via Caravel LA pins | Up to 128 LA pins available |
| GPIO | `busy`, `fault`, `done` summary bits | 3 GPIO pins for status LED or external monitoring |

## Design rules

1. Counters increment on the **same clock edge** as the event they count -- no asynchronous sampling.
2. Probe signals are **directly wired** from source flip-flops -- no combinational logic in the probe path.
3. All debug state clears cleanly on `rst_n` and `soft_reset`.
4. Debug infrastructure must **not** appear on the critical timing path. Counters and probes tap existing registered signals only.
5. Every simulation run and FPGA experiment report must record which counters and probes were active.

## Verification plan

| Test category | Method | Sprint |
| --- | --- | --- |
| Counter increment correctness | Directed cocotb: run known workload, verify counter values | 07 |
| Counter saturation | Directed cocotb: drive counter to 0xFFFFFFFF, verify no wrap | 07 |
| Counter reset | Directed cocotb: soft_reset clears all counters | 07 |
| STATUS register fields | Directed cocotb: verify busy/fault/dma_active/compute_active | 07 |
| FAULT_INFO capture | Directed cocotb: inject fault, read FAULT_INFO, verify fields | 05 |
| Probe signal stability | Formal: probes are always registered (no glitch) | 06 |
| Debug tap mux | Directed cocotb: set DEBUG_SEL, verify correct probe group | 08 |
