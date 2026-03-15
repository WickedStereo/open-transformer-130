# Verification Matrix

Date: 2026-03-15
Report type: verification planning
Sprint: 02

## Purpose

Map every RTL block to its verification targets across unit tests, formal properties, integration tests, and coverage goals. This matrix is the contract between microarchitecture and verification -- no block enters RTL without a test plan.

## Block verification matrix

### MAC lane (`mac_lane`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Multiply correctness: 0, 1, -1, 127, -128, random | Directed cocotb | 03 | `a * b` (Python int) |
| Unit | Accumulate and saturation: overflow to INT32_MAX/MIN | Directed cocotb | 03 | `saturate(sum, 32)` |
| Unit | Accumulator clear on `accum_clear` | Directed cocotb | 03 | exact match |
| Unit | Pipeline latency: 3-cycle valid propagation | Directed cocotb | 03 | timing check |
| Formal | Accumulator never exceeds INT32 range without saturation | SymbiYosys assert | 06 | — |
| Coverage | All operand-sign combinations exercised | cocotb + coverage | 03 | — |

### MAC array (`mac_array`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | 4x4 tile multiply | Directed cocotb | 03 | `int_matmul()` |
| Unit | 16x16 tile multiply | Directed cocotb | 03 | `int_matmul()` |
| Unit | 64x64 tile multiply (full baseline) | Directed cocotb | 03 | `int_matmul()` |
| Unit | Accumulate mode: back-to-back tiles | Directed cocotb | 03 | `int_matmul()` with accum |
| Unit | Backpressure: toggle `result_ready` | Constrained-random | 03 | no data loss |
| Unit | Non-square tiles (boundary handling) | Directed cocotb | 03 | `int_matmul()` |
| Integration | Array + scratchpad writeback | Directed cocotb | 07 | `int_matmul()` |
| Synthesis | Timing at 150 MHz | Yosys + OpenSTA | 03 | — |

### Scratchpad (`scratchpad`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Single-bank read/write | Directed cocotb | 04 | exact byte match |
| Unit | All 8 banks independently | Directed cocotb | 04 | exact byte match |
| Unit | Full 4 KiB tile write/read | Directed cocotb | 04 | exact byte match |
| Unit | Bank address decode correctness | Directed cocotb | 04 | `ScratchpadModel.bank_for_address()` |
| Formal | No access to bank index >= 8 | SymbiYosys assert | 06 | — |

### Bank arbiter (`bank_arbiter`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | DMA wins over MAC and vector on same bank | Directed cocotb | 04 | priority check |
| Unit | MAC wins over vector on same bank | Directed cocotb | 04 | priority check |
| Unit | No-conflict: all three access different banks | Directed cocotb | 04 | all granted |
| Unit | Stall-based backpressure: denied request held stable | Constrained-random | 04 | no data loss |
| Formal | Grant is mutually exclusive per bank per cycle | SymbiYosys assert | 06 | — |
| Formal | Every held request is eventually granted (no starvation) | SymbiYosys liveness | 06 | — |
| Coverage | All 3-requester conflict combinations | cocotb + coverage | 04 | — |

### DMA engine (`dma_engine`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Load: 4096-byte tile, verify scratchpad contents | Directed cocotb | 04 | byte-exact |
| Unit | Store: scratchpad to host, verify host memory | Directed cocotb | 04 | byte-exact |
| Unit | OOB fault: slot_id = 32 | Directed cocotb | 04 | error pulse |
| Unit | Byte counter: verify `bytes_moved` after transfer | Directed cocotb | 04 | exact count |
| Unit | Back-to-back transfers | Directed cocotb | 04 | no gap in data |
| Formal | Every cmd_valid eventually produces done or error | SymbiYosys liveness | 06 | — |
| Formal | No scratchpad address >= 131072 | SymbiYosys assert | 06 | — |
| Coverage | Load and store, various byte_count values | cocotb + coverage | 04 | — |

### Decoder (`decoder`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | All 8 valid opcodes decode correctly | Directed cocotb | 05 | decode table |
| Unit | Invalid opcode (0x08, 0x80, 0xFF) -> fault | Directed cocotb | 05 | INVALID_OPCODE |
| Unit | Reserved field nonzero -> fault | Directed cocotb | 05 | RESERVED_FIELD |
| Unit | OOB tile ID (32, 255) -> fault | Directed cocotb | 05 | TILE_OOB |
| Unit | Fault priority: reserved > opcode > tile | Directed cocotb | 05 | first wins |
| Formal | Every descriptor produces exactly one action or fault | SymbiYosys assert | 06 | — |
| Coverage | All opcode x flag combinations | cocotb + coverage | 05 | — |

### Command queue controller (`queue_ctrl`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Single-entry queue: post and consume | Directed cocotb | 05 | exact match |
| Unit | Full queue: 256 entries, wrap-around | Directed cocotb | 05 | exact match |
| Unit | Empty queue: tail == head, no fetch | Directed cocotb | 05 | no desc_valid |
| Unit | Fault halts consumption | Directed cocotb | 05 | tail frozen |
| Formal | tail never passes head | SymbiYosys assert | 06 | — |
| Coverage | Queue depth 1, 2, 128, 256 | cocotb + coverage | 05 | — |

### Tile scheduler (`tile_scheduler`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | IDLE -> COMPUTE -> IDLE for MATMUL on resident tiles | Directed cocotb | 07 | FSM trace |
| Unit | Full attention: LOAD, MATMUL, SOFTMAX, STORE | Directed cocotb | 07 | `tiled_attention()` |
| Unit | BARRIER drains in-flight work | Directed cocotb | 07 | busy -> idle |
| Unit | Hazard: stall on LOADING slot | Directed cocotb | 07 | no read until RESIDENT |
| Formal | No deadlock: every state has an enabled exit | SymbiYosys liveness | 06 | — |
| Formal | No hazard violation: no read of LOADING slot | SymbiYosys assert | 06 | — |
| Integration | End-to-end command trace | Directed cocotb | 07 | `tiled_attention()` |
| Coverage | All FSM state transitions | cocotb + coverage | 07 | — |

### Vector/softmax unit (`vector_unit`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Row-max reduction | Directed cocotb | 05 | `np.max()` |
| Unit | Exp approximation accuracy | Directed cocotb | 05 | `np.exp()`, cosine > 0.99 |
| Unit | Full softmax row | Directed cocotb | 05 | `reference_attention.softmax()` |
| Unit | Extreme inputs: large negatives, all-equal, single-hot | Directed cocotb | 05 | golden model |
| Unit | 64x64 tile softmax | Directed cocotb | 05 | `reference_attention.softmax()` |
| Unit | Arbiter backpressure | Constrained-random | 05 | no data loss |
| Formal | No NaN/Inf equivalent in output | SymbiYosys assert | 06 | — |
| Coverage | Score distributions: uniform, skewed, sparse | cocotb + coverage | 05 | — |

### MMIO registers (`mmio_regs`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Write/read all RW registers | Directed cocotb | 05 | exact match |
| Unit | Read-only registers reject writes | Directed cocotb | 05 | value unchanged |
| Unit | Reset values correct | Directed cocotb | 05 | reset table |
| Unit | Soft reset clears counters | Directed cocotb | 05 | all zero |
| Integration | Register model vs. command-driven workload | Directed cocotb | 07 | expected values |

### Debug/observability (`debug_counters`, `debug_probes`)

| Category | Target | Method | Sprint | Golden ref |
| --- | --- | --- | --- | --- |
| Unit | Counter increment on event | Directed cocotb | 07 | exact count |
| Unit | Counter saturation at 0xFFFFFFFF | Directed cocotb | 07 | no wrap |
| Unit | Counter clear on soft_reset | Directed cocotb | 07 | zero |
| Unit | Probe signal stability | Directed cocotb | 07 | registered |
| Formal | Counter monotonic (no decrement except reset) | SymbiYosys assert | 06 | — |

## Summary by sprint

| Sprint | Block | Unit tests | Formal | Integration | Coverage |
| --- | --- | --- | --- | --- | --- |
| 03 | mac_lane, mac_array | 12 | — | — | operand signs |
| 04 | scratchpad, arbiter, DMA | 14 | — | — | conflict combos |
| 05 | decoder, queue_ctrl, vector, MMIO | 18 | — | — | opcode x flags |
| 06 | all blocks | — | 16 | — | — |
| 07 | scheduler, debug, integration | 10 | — | 3 | FSM states |

Total planned verification items: **73** (54 unit, 16 formal, 3 integration).
