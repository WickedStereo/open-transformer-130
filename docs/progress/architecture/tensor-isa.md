# Tensor ISA

Status: implemented baseline with integration profile
Date frozen: 2026-03-15

## Goals

The tensor ISA should be simple enough for early bring-up, expressive enough for tiled attention execution, and stable enough to survive migration from stand-alone simulation to Caravel integration.

## Frozen opcode set

| Opcode | Value | Purpose |
| --- | --- | --- |
| `NOP` | `0x00` | No operation; consumed and discarded by decoder |
| `LOAD_TILE` | `0x01` | DMA transfer from host memory into scratchpad |
| `STORE_TILE` | `0x02` | DMA transfer from scratchpad to host memory |
| `MATMUL` | `0x03` | Tiled INT8 matrix multiply; current integrated profile overwrites the RHS slot after prefetch |
| `ACCUMULATE` | `0x04` | Partial-sum reduction or accumulator merge |
| `SOFTMAX` | `0x05` | Row-wise softmax via vector/reduction path |
| `CONFIG` | `0x06` | Write to a control/configuration register |
| `BARRIER` | `0x07` | Ordering fence across dependent operations |
| Reserved | `0x08-0xFF` | Decoder must reject with fault; reserved for future use |

## Command descriptor format (64-bit)

All commands use a fixed 64-bit descriptor word.

```
Bits    Field           Width   Description
──────────────────────────────────────────────────────────
63:56   opcode          8       Operation code from table above
55:48   flags           8       Per-opcode modifier flags (see below)
47:40   dst_tile_id     8       Destination scratchpad tile slot (0-31)
39:32   src_tile_id     8       Source scratchpad tile slot (0-31)
31:24   dim_m           8       Tile M dimension (1-255, 0 = use configured default)
23:16   dim_n           8       Tile N dimension (1-255, 0 = use configured default)
15:8    dim_k           8       Tile K dimension for MATMUL (1-255, 0 = use default)
7:4     tag             4       Completion tag for status tracking
3:0     reserved        4       Must be zero; decoder faults on nonzero
```

## Per-opcode flag definitions

| Opcode | Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bits 3:0 |
| --- | --- | --- | --- | --- | --- |
| `LOAD_TILE` | burst_mode | — | — | — | reserved |
| `STORE_TILE` | burst_mode | — | — | — | reserved |
| `MATMUL` | accumulate (decoded, reserved in current integrated top) | saturate | reserved | reserved | right_shift |
| `ACCUMULATE` | reset_after | — | — | — | reduction_mode[3:0] |
| `SOFTMAX` | approx_mode | — | — | — | reserved |
| `CONFIG` | — | — | — | — | register_id[3:0] |
| `BARRIER` | flush_queue | — | — | — | scope[3:0] |

## Integrated MATMUL profile

The current integrated core uses the existing two-slot descriptor format with this execution contract:

- `src_tile_id`: left-hand-side tile (`A`)
- `dst_tile_id`: right-hand-side tile (`B`) and in-place destination for the output tile (`C`)

The compute engine therefore **prefetches the RHS tile before any writes occur** and then overwrites the `dst_tile_id` slot with the INT8 output tile. This keeps the queue format compact while the software/runtime stack is still immature.

## Scratchpad tile addressing

- Tile slot IDs 0-31 are valid; IDs 32-255 are reserved and cause a fault.
- Each slot maps to a contiguous region: `base_addr = slot_id * 4096`.
- The current integrated baseline uses a fixed 4 KiB slot capacity.
- The addressing scheme is deterministic and software-visible.

## MMIO register map

| Offset | Name | R/W | Description |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | RW | Global enable, reset, interrupt mask |
| `0x04` | `STATUS` | RO | Queue depth, busy, fault flags |
| `0x08` | `CMD_QUEUE_BASE` | RW | Host-physical base address of command ring |
| `0x0C` | `CMD_QUEUE_SIZE` | RW | Queue depth (power of 2, max 256) |
| `0x10` | `CMD_HEAD` | RW | Producer write pointer |
| `0x14` | `CMD_TAIL` | RO | Consumer read pointer |
| `0x18` | `FAULT_INFO` | RO | Last fault opcode, descriptor, and cause |
| `0x1C` | `TILE_DEFAULT_M` | RW | Default tile M when descriptor says 0 |
| `0x20` | `TILE_DEFAULT_N` | RW | Default tile N when descriptor says 0 |
| `0x24` | `TILE_DEFAULT_K` | RW | Default tile K when descriptor says 0 |
| `0x28` | `PERF_BUSY_CYCLES` | RO | Saturating counter: cycles with active compute |
| `0x2C` | `PERF_STALL_CYCLES` | RO | Saturating counter: cycles stalled on memory/control |
| `0x30` | `PERF_DMA_BYTES` | RO | Saturating counter: total DMA bytes transferred |
| `0x34` | `PERF_TILE_COUNT` | RO | Saturating counter: tiles completed |
| `0x38` | `DMA_HOST_ADDR` | RW | Base host address; queued DMA uses `DMA_HOST_ADDR + slot_id * 4096` |
| `0x3C` | `SCRATCH_BASE` | RW | Reserved for future direct-mode transfers |

## Programming model

1. Software writes `CMD_QUEUE_BASE` and `CMD_QUEUE_SIZE` to configure the command ring.
2. Software fills descriptors into the ring and advances `CMD_HEAD`.
3. Hardware consumes descriptors from `CMD_TAIL` to `CMD_HEAD`, advancing `CMD_TAIL`.
4. `STATUS` reflects queue occupancy, active state, and fault indicators.

For queued DMA traffic in the current integrated core, software lays out host-memory tiles at `DMA_HOST_ADDR + slot_id * 4096`.

## Invalid-command policy

- **Unknown opcode**: Decoder sets `FAULT_INFO` with cause `INVALID_OPCODE`, halts queue consumption, and asserts fault in `STATUS`.
- **Reserved field nonzero**: Decoder sets `FAULT_INFO` with cause `RESERVED_FIELD`, halts queue consumption.
- **Out-of-range tile ID**: Decoder sets `FAULT_INFO` with cause `TILE_OOB`, halts queue consumption.
- **Software must clear faults** by writing `1` to the fault-clear bit in `CTRL` before the queue resumes.
- All fault causes are mutually exclusive per descriptor; the first detected fault wins.

## Sprint outputs tied to this ISA

- Sprint 1: opcode set, descriptor format, register map, and invalid-command policy frozen.
- Sprint 2: bind fields to decoder and scheduler interfaces.
- Sprint 5: validate decoder behavior and vector-path control.
- Sprint 10: expose the finalized programming model through Caravel-facing registers.
