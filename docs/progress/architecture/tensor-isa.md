# Tensor ISA

## Goals

The tensor ISA should be simple enough for early bring-up, expressive enough for tiled attention execution, and stable enough to survive migration from stand-alone simulation to Caravel integration.

## Proposed instruction classes

| Instruction | Purpose | Likely operands |
| --- | --- | --- |
| `LOAD_TILE` | Move a tile from host memory into scratchpad | host address, scratchpad address, shape, stride |
| `MATMUL` | Execute tiled matrix multiply for attention score or value path | source tile ids, accumulation mode, shape |
| `ACCUMULATE` | Combine partial sums or reduction results | source/destination tile ids, reduction flags |
| `SOFTMAX` | Launch the vector/reduction path for attention normalization | source tile id, approximation mode, axis |
| `STORE_TILE` | Write a completed tile back to host memory | scratchpad address, host address, shape |
| `CONFIG` | Program mode bits, precision, bounds, or debug controls | register id, value |
| `BARRIER` | Order dependent work and enable deterministic completion semantics | barrier id or queue scope |

## Descriptor shape

A practical first command format should include:

- opcode
- source and destination scratchpad identifiers
- host address base or descriptor pointer when memory is involved
- tile shape metadata such as `M`, `N`, and `K`
- flags for accumulation, activation, approximation, or saturation behavior
- context or tag field for completion tracking and debug

## Programming model

- Software writes MMIO registers to configure queue base, queue depth, interrupt/control policy, and status clears.
- Commands are posted into a queue that hardware consumes asynchronously.
- Status registers expose queue state, faults, and performance counters.
- For earliest bring-up, a direct register-triggered single-command path may coexist with the queued path.

## Correctness constraints

- Commands must not allow out-of-range scratchpad accesses.
- Memory transfers must preserve alignment and shape semantics defined by software.
- Decoder behavior must be deterministic for invalid opcodes and reserved fields.
- Numerical modes must map directly to golden-model comparison settings.

## Sprint outputs tied to this ISA

- Sprint 1: freeze opcode set and descriptor fields.
- Sprint 2: bind fields to decoder and scheduler interfaces.
- Sprint 5: validate decoder behavior and vector-path control.
- Sprint 10: expose the finalized programming model through Caravel-facing registers.
