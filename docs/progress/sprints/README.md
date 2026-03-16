# Sprint Plans

All sprint documents below are written to enable parallel execution across architecture, RTL, verification, software, and integration lanes where dependencies allow.

| Sprint | Theme | Status | Document |
| --- | --- | --- | --- |
| 00 | Repository Bootstrap | done | [Sprint 00 - Repository Bootstrap](sprint-00-bootstrap.md) |
| 01 | Architecture Exploration | done | [Sprint 01 - Architecture Exploration](sprint-01-architecture-exploration.md) |
| 02 | Microarchitecture Design | done | [Sprint 02 - Microarchitecture Design](sprint-02-microarchitecture.md) |
| 03 | MAC Array RTL | done | [Sprint 03 - MAC Array RTL](sprint-03-mac-array-rtl.md) |
| 04 | Memory Subsystem RTL | skipped for current non-ASIC scope | [Sprint 04 - Memory Subsystem RTL](sprint-04-memory-subsystem-rtl.md) |
| 05 | Vector Operations | done | [Sprint 05 - Vector Operations](sprint-05-vector-operations.md) |
| 06 | Formal Verification | done (bounded `cvc4` suite green) | [Sprint 06 - Formal Verification](sprint-06-formal-verification.md) |
| 07 | System Integration | done (full single-tile Q/K/V path) | [Sprint 07 - System Integration](sprint-07-system-integration.md) |
| 08 | FPGA Prototype | done (compact iCEBreaker demo bitstream) | [Sprint 08 - FPGA Prototype](sprint-08-fpga-prototype.md) |
| 09 | Compiler and Runtime | done (runtime + lowering baseline) | [Sprint 09 - Compiler and Runtime](sprint-09-compiler-runtime.md) |
| 10 | Caravel Integration | skipped for current non-ASIC scope | [Sprint 10 - Caravel Integration](sprint-10-caravel-integration.md) |
| 11 | Physical Design | skipped for current non-ASIC scope | [Sprint 11 - Physical Design](sprint-11-physical-design.md) |
| 12 | Tapeout Preparation | skipped for current non-ASIC scope | [Sprint 12 - Tapeout Preparation](sprint-12-tapeout-preparation.md) |
| 13 | Post-Silicon Validation | skipped for current non-ASIC scope | [Sprint 13 - Post-Silicon Validation](sprint-13-post-silicon.md) |

## Rebaseline Notes

The numbering is intentionally preserved. What changed after the de-risking work and the current non-ASIC close-out request is the interpretation of which sprints are in scope and the evidence required to exit them.

- `Sprint 04` and `Sprint 10` through `Sprint 13` are intentionally out of scope for this phase because they are ASIC-implementation or post-silicon lanes.
- `Sprint 06` is closed for the current scope: `make formal` is green with bounded `cvc4` proofs, and the scheduler report now reflects the reduced harness assumptions used for closure.
- `Sprint 07` is complete for the current non-ASIC target because the repo now demonstrates the full single-tile `Q -> K^T -> score -> softmax -> V -> output store` path.
- `Sprint 08` still has two layers conceptually: `08A` fast synthesis / elaboration evidence and `08B` board-specific bring-up. Both are now closed for the current scope via the compact iCEBreaker demo path and reproducible bitstream generation.
- `Sprint 09` is now beyond the original "thin-runtime first" gate: runtime helpers, descriptor serialization, attention lowering, and ONNX pattern extraction all exist, with future work limited to wider model coverage.

## Near-Term Execution Order

For the current integrated prototype and current user scope, the highest-value order is:

1. Extend `Sprint 09` from the current working baseline toward broader model coverage.
2. Keep the `Sprint 06` and `Sprint 08` evidence green as the RTL evolves.
3. Keep ASIC-only sprints deferred until the non-ASIC baseline changes scope again.

## Evidence Gates

Use these gates instead of treating sprint completion as "code exists":

- `Sprint 06` exit: `make formal` passes with a real SMT solver and CI records proof results.
- `Sprint 07` exit: integrated execution covers the current single-tile Q/K/V attention fragment end to end.
- `Sprint 08` exit: `make fpga-demo-elab` stays reproducible and the board-specific bitstream/demo flow is no longer blocked by wrapper/tooling issues.
- `Sprint 09` exit: software can emit, stage, and validate the current integrated workload without handwritten descriptor assembly.

Use [../templates/sprint-template.md](../templates/sprint-template.md) for future additions or replacements once the template is populated.
