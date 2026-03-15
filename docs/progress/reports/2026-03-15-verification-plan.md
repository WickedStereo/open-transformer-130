# Verification Comparison Plan

Date: 2026-03-15
Report type: verification planning
Sprint: 01

## Objective

Define how golden-model outputs will be compared against future RTL block implementations, specifying scoreboard structure, test vectors, and numeric acceptance criteria.

## Comparison hierarchy

Verification proceeds in layers. Each layer has a golden-model checkpoint and a defined comparison method.

### Layer 1: Numeric primitives

| Block | Golden model function | Comparison |
| --- | --- | --- |
| INT8 multiply | `a * b` (Python int) | exact match |
| INT32 accumulate | `sum(a_i * b_i)` with saturation | exact match |
| Softmax (float ref) | `reference_attention.softmax()` | cosine > 0.999, abs < 1e-4 |
| Softmax (fixed-point approx) | TBD (Sprint 05) | cosine > 0.99, abs < 0.1 |

### Layer 2: Tile-level operations

| Block | Golden model function | Comparison |
| --- | --- | --- |
| Tiled matmul | `reference_attention.int_matmul()` | exact match (integer path) |
| Tiled attention (one Q-block) | `reference_attention.tiled_attention()` one outer iteration | cosine > 0.99, abs < 1.0 |
| Full tiled attention | `reference_attention.tiled_attention()` | cosine > 0.90, abs < 20.0 |

### Layer 3: System-level operations

| Block | Golden model function | Comparison |
| --- | --- | --- |
| End-to-end command sequence | `tiled_attention()` driven by ISA command trace | cosine > 0.90 |
| DMA data integrity | byte-exact scratchpad image | exact match |
| Control/status registers | expected register values from command sequence | exact match |

## Scoreboard structure

The verification scoreboard will be implemented as a Python class consumed by cocotb testbenches.

```
Scoreboard
├── input_stimulus      # Q, K, V matrices and command sequence
├── golden_outputs      # reference_attention outputs for each comparison point
├── dut_outputs         # captured from DUT via cocotb
├── comparison_results  # ComparisonResult objects from compare()
└── pass_fail_summary   # aggregate verdict
```

Key properties:
- The scoreboard stores stimulus, golden reference, and DUT output for post-mortem analysis.
- Comparison uses `reference_attention.compare()` with per-layer thresholds.
- Failed comparisons dump the full input/golden/dut triple for debugging.

## Test vector plan

### Block-level vectors (Sprint 03-05)

| Vector set | Description | Count |
| --- | --- | --- |
| MAC unit directed | Boundary values: 0, 1, -1, 127, -128, max accumulation | 16 |
| MAC unit random | Uniformly distributed INT8 operands, varying dot-product length | 64 |
| Softmax directed | All-equal, single-hot, large-negative, overflow-adjacent | 8 |
| Softmax random | Random INT32 score rows of varying length | 32 |
| DMA directed | Single-byte, full-tile, misaligned (if supported), back-to-back | 8 |

### Tile-level vectors (Sprint 07)

| Vector set | Description | Count |
| --- | --- | --- |
| Small attention | seq=4, d=4, single tile | 4 |
| Multi-tile attention | seq=16, d=8, 2x2 tiling | 4 |
| Full baseline | seq=128, d=64, 2x2 tiling at 64x64 | 2 |
| Boundary tiles | Non-square remainders at sequence edges | 4 |

### System-level vectors (Sprint 07+)

| Vector set | Description | Count |
| --- | --- | --- |
| Command-queue smoke | NOP, CONFIG, BARRIER sequences | 4 |
| Attention command trace | Full LOAD/MATMUL/SOFTMAX/STORE sequence | 2 |
| Fault injection | Invalid opcode, OOB tile ID, reserved-field nonzero | 6 |
| Performance counter | Verify busy/stall/DMA/tile counters after known workload | 2 |

## Golden-model checkpoints for RTL blocks

Each RTL block being implemented in Sprints 03-05 must have a corresponding golden-model function and comparison threshold committed before RTL coding begins.

| RTL block | Golden function | Threshold | Sprint |
| --- | --- | --- | --- |
| `mac_lane` | `int_matmul` (single row) | exact | 03 |
| `mac_array` | `int_matmul` (full tile) | exact | 03 |
| `accumulator` | `saturate()` | exact | 03 |
| `scratchpad` | `ScratchpadModel` addressing | exact | 04 |
| `dma_engine` | byte-level data transfer | exact | 04 |
| `softmax_unit` | `softmax()` | cosine > 0.99 | 05 |
| `decoder` | opcode -> action mapping | exact | 05 |
| `attn_core` | `tiled_attention()` | cosine > 0.90 | 07 |

## Architecture assumptions needing formal support

The following assumptions should be proven or bounded by formal verification in Sprint 06:

1. **No scratchpad OOB access**: DMA and scheduler never issue addresses outside allocated tile slots.
2. **No accumulator overflow without saturation**: the saturate path is always on the critical data path.
3. **No scheduler deadlock**: the tile scheduler cannot enter a state where no progress is possible.
4. **Command queue liveness**: if commands are posted and no fault occurs, they are eventually consumed.
5. **Fault determinism**: each fault cause maps to exactly one fault code in `FAULT_INFO`.

## Tools and infrastructure

- **Golden model**: `sim/reference_attention.py` (Python/NumPy)
- **Comparison**: `reference_attention.compare()` with `ComparisonResult`
- **Test framework**: cocotb + pytest
- **Waveform**: VCD/FST via Verilator
- **Formal**: SymbiYosys (Sprint 06)
- **Regression**: `make test` runs all cocotb and numeric tests
