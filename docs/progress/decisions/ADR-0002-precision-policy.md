# ADR-0002 - INT8 Operands with INT32 Accumulation

Date: 2026-03-15
Status: accepted

## Context

The accelerator needs a fixed precision policy for the MAC array, accumulator path, and softmax pipeline before RTL design can begin. The master plan proposed INT8 operands with INT16-or-wider accumulation, pending numeric study results.

## Decision

Adopt **INT8 operands with INT32 internal accumulation** as the baseline precision policy.

- MAC array inputs: signed 8-bit integers (range -128 to 127).
- MAC accumulator: signed 32-bit integer.
- Softmax intermediate values: 16-bit fixed-point internally, with float-equivalent precision in the golden model for verification.
- Output writeback: INT8 after saturation and optional right-shift scaling.

## Rationale

The numeric study (`sim/test_numeric_study.py`) compared float, INT8/INT16-accum, and INT8/INT32-accum attention across workloads from seq_len=16 to seq_len=128:

- INT16 and INT32 accumulators produce **identical** outputs at the tested dimensions because INT8 x INT8 dot products over d_model=64 do not overflow INT16 for these workload scales.
- However, at d_model=128 or with adversarial inputs, INT16 accumulation risks silent overflow and saturation-induced error.
- INT32 accumulation adds modest area (wider adder tree) but eliminates overflow risk for all planned tile shapes up to 128x128.
- Cosine similarity between INT8-quantized and float reference stays above 0.92 across all tested configurations, which is acceptable for attention workloads.

The cost of INT32 over INT16 is a wider accumulator register file and adder tree. At 16 MAC lanes with 32-bit accumulators, this is approximately 512 bits of register state per lane -- manageable on SKY130.

## Alternatives Considered

- **INT16 accumulation**: Lower area but risks silent overflow at larger d_model or adversarial inputs. Rejected for safety.
- **FP16 operands**: Higher precision but 4x the multiplier area on SKY130. Rejected for first tapeout; could be revisited in a future generation.
- **Mixed INT8/FP16**: Complexity of dual datapaths outweighs benefit at this stage. Rejected.

## Consequences

- The MAC lane design targets 8x8 -> 32-bit multiply-accumulate.
- Softmax and vector operations consume INT32 accumulator outputs.
- The golden model's `PrecisionConfig(input_bits=8, accumulator=INT32)` is the verification reference.
- The numeric study thresholds (cosine > 0.90, max_abs < 20) become the pass/fail contract between golden model and RTL.

## Follow-Up

- [sim/reference_attention.py](../../../sim/reference_attention.py): `PrecisionConfig` encodes this decision.
- [sim/test_numeric_study.py](../../../sim/test_numeric_study.py): automated regression for the numeric contract.
- Sprint 03 MAC array RTL must implement `int8 * int8 -> int32` accumulation.
- Sprint 05 softmax path must consume INT32 inputs.
