# Architecture Study Report

Date: 2026-03-15
Report type: architecture exploration
Sprint: 01

## Objective

Evaluate and freeze the first credible architecture baseline by sweeping tile sizes, precision options, and scratchpad configurations against workload requirements.

## Methodology

Three analysis paths ran in parallel:

1. **Numeric study** (`sim/test_numeric_study.py`): compared float, INT8/INT16-accum, INT8/INT32-accum, and tiled-quantized attention across representative workloads.
2. **Performance model** (`sim/performance_model.py`): analytical estimation of MAC utilization, DMA traffic, and latency across tile sizes and DMA overlap assumptions.
3. **Scratchpad feasibility** (`ScratchpadModel` in `sim/reference_attention.py`): capacity analysis for double-buffering across tile sizes.

## Precision study results

| Configuration | Max abs error | Mean abs error | Cosine similarity | Status |
| --- | --- | --- | --- | --- |
| INT8/INT16 accum, seq=64, d=64 | 16.7 | 0.75 | 0.951 | acceptable |
| INT8/INT32 accum, seq=64, d=64 | 16.7 | 0.75 | 0.951 | acceptable |
| INT8/INT32 accum, seq=128, d=64 | 18.1 | 0.99 | 0.920 | acceptable |

Key findings:

- INT16 and INT32 accumulators produce identical results at d_model=64 because no overflow occurs. However, INT32 is chosen for safety at larger dimensions.
- Quantization error is dominated by the INT8 input rounding, not accumulator width. The cosine similarity above 0.90 is the acceptance threshold.
- Tiled execution with online softmax matches non-tiled quantized attention to machine precision (cosine > 0.9999), validating the FlashAttention-style dataflow.

## Tile-size sweep results (seq=128, d=64, 150 MHz, 16 MACs)

| Tile | Compute cycles | DMA cycles | Scheduler cycles | Total cycles | MAC util | GOPS | Tiles in 128K |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 8x8 | 132,608 | 33,432 | 4,096 | 153,420 | 85.4% | 2.05 | 2048 |
| 16x16 | 131,456 | 18,975 | 1,024 | 141,967 | 92.3% | 2.22 | 512 |
| 32x32 | 131,168 | 11,747 | 256 | 137,297 | 95.5% | 2.29 | 128 |
| **64x64** | **131,096** | **8,133** | **64** | **135,226** | **96.9%** | **2.33** | **32** |
| 128x128 | 131,078 | 6,326 | 16 | 134,257 | 97.6% | 2.34 | 8 |

## DMA overlap sensitivity (64x64 tile)

| DMA-compute overlap | Total cycles | MAC utilization |
| --- | --- | --- |
| 0% | 139,293 | 94.1% |
| 25% | 137,259 | 95.5% |
| 50% | 135,226 | 96.9% |
| 75% | 133,193 | 98.4% |
| 100% | 131,160 | 99.9% |

The design is compute-bound. Even with zero DMA overlap, utilization exceeds 94%.

## Scratchpad capacity analysis

| Tile | Bytes per tile | Tiles in 128 KiB | Double-buffer (4 tiles) |
| --- | --- | --- | --- |
| 32x32 | 1,024 | 128 | yes |
| 64x64 | 4,096 | 32 | yes |
| 128x128 | 16,384 | 8 | yes (marginal) |

At 64x64, 32 slots leave 28 for prefetch after allocating the 4-tile working set.

## Chosen baseline

| Parameter | Value | Rationale |
| --- | --- | --- |
| Operand type | INT8 | Standard for efficient attention inference |
| Accumulator | INT32 | Overflow-safe for all planned tile shapes |
| Tile shape | 64x64 | 96.9% utilization, 32 scratchpad slots, comfortable double-buffering |
| Scratchpad | 128 KiB, 8 banks | Adequate for compute-bound design; 32 tile slots |
| Control model | MMIO command queue, 64-bit descriptors | 8-opcode ISA with deterministic fault handling |
| Target frequency | ~150 MHz on SKY130 | Planning target, refined after synthesis |
| MAC lanes | 16 | Matches tile width / 4 cycles per row |

## Rejected alternatives

| Option | Why rejected |
| --- | --- |
| INT16 accumulator | Overflow risk at larger d_model; negligible area savings |
| FP16 operands | 4x multiplier area on SKY130; not justified for first tapeout |
| 32x32 tiles | 4x scheduler overhead for only 1.4% less utilization |
| 128x128 tiles | Only 8 scratchpad slots; marginal double-buffering headroom |
| 256 KiB scratchpad | May not fit SKY130 Caravel area budget |
| Cache-based memory | Coherence complexity not justified for a tiled accelerator |

## Risks carried forward

- SKY130 area and routing may force compromises on MAC lane count or scratchpad capacity.
- The 150 MHz target is a planning assumption; synthesis in Sprint 11 will produce the real number.
- Softmax approximation strategy is deferred to Sprint 02/05 microarchitecture work.
- The numeric study uses uniformly distributed random inputs; real transformer activations may have different distributions.

## Evidence artifacts

- [sim/reference_attention.py](../../../sim/reference_attention.py): expanded golden model
- [sim/performance_model.py](../../../sim/performance_model.py): analytical performance model
- [sim/test_numeric_study.py](../../../sim/test_numeric_study.py): automated numeric study
- [ADR-0002](../decisions/ADR-0002-precision-policy.md): precision decision
- [ADR-0003](../decisions/ADR-0003-tile-shape.md): tile shape decision
- [ADR-0004](../decisions/ADR-0004-scratchpad-organization.md): scratchpad decision
- [Tensor ISA](../architecture/tensor-isa.md): frozen ISA specification
