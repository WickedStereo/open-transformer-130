# Sprint Plans

All sprint documents below are written to enable parallel execution across architecture, RTL, verification, software, and integration lanes where dependencies allow.

| Sprint | Theme | Status | Document |
| --- | --- | --- | --- |
| 00 | Repository Bootstrap | done | [Sprint 00 - Repository Bootstrap](sprint-00-bootstrap.md) |
| 01 | Architecture Exploration | done | [Sprint 01 - Architecture Exploration](sprint-01-architecture-exploration.md) |
| 02 | Microarchitecture Design | done | [Sprint 02 - Microarchitecture Design](sprint-02-microarchitecture.md) |
| 03 | MAC Array RTL | done | [Sprint 03 - MAC Array RTL](sprint-03-mac-array-rtl.md) |
| 04 | Memory Subsystem RTL | active | [Sprint 04 - Memory Subsystem RTL](sprint-04-memory-subsystem-rtl.md) |
| 05 | Vector Operations | done | [Sprint 05 - Vector Operations](sprint-05-vector-operations.md) |
| 06 | Formal Verification | active | [Sprint 06 - Formal Verification](sprint-06-formal-verification.md) |
| 07 | System Integration | done (baseline closure) | [Sprint 07 - System Integration](sprint-07-system-integration.md) |
| 08 | FPGA Prototype | active | [Sprint 08 - FPGA Prototype](sprint-08-fpga-prototype.md) |
| 09 | Compiler and Runtime | planned (thin-runtime first) | [Sprint 09 - Compiler and Runtime](sprint-09-compiler-runtime.md) |
| 10 | Caravel Integration | planned | [Sprint 10 - Caravel Integration](sprint-10-caravel-integration.md) |
| 11 | Physical Design | active | [Sprint 11 - Physical Design](sprint-11-physical-design.md) |
| 12 | Tapeout Preparation | planned | [Sprint 12 - Tapeout Preparation](sprint-12-tapeout-preparation.md) |
| 13 | Post-Silicon Validation | planned | [Sprint 13 - Post-Silicon Validation](sprint-13-post-silicon.md) |

## Rebaseline Notes

The numbering is intentionally preserved. What changed after the de-risking work is the interpretation of the active sprints and the evidence required to exit them.

- `Sprint 04` stays active until the memory subsystem has a credible SRAM macro integration path, not just corrected behavioral RTL.
- `Sprint 06` stays active until solver-backed formal runs complete in CI. Harness attachment alone is not enough.
- `Sprint 07` is considered complete for baseline integration because the repo now demonstrates `LOAD_TILE -> MATMUL -> SOFTMAX -> STORE_TILE`, but it is not the same as full attention datapath closure.
- `Sprint 08` should be read as two layers: `08A` synthesis / FPGA smoke and debugability, then `08B` board-specific wrapper and bring-up.
- `Sprint 09` should begin with a minimal command generator / runtime path before any broader compiler ambition.
- `Sprint 11` is also two layers: `11A` backend evidence on `attn_core` now, then `11B` full physical closure once the integration target is more stable.

## Near-Term Execution Order

For the current integrated prototype, the highest-value order is:

1. Close `Sprint 06` with real solver-backed formal results.
2. Advance `Sprint 11A` and `Sprint 08A` by collecting synthesis/OpenLane evidence on `attn_core`.
3. Finish the remaining `Sprint 04` memory realism work around SRAM macro integration.
4. Extend `Sprint 07` behaviorally toward a fuller attention sequence.
5. Start `Sprint 09A` with a thin software/runtime bring-up layer.
6. Hold `Sprint 10` until the core is more physically credible.

## Evidence Gates

Use these gates instead of treating sprint completion as "code exists":

- `Sprint 04` exit: scratchpad wrapper boundary plus a defined macro replacement path and backend-relevant memory collateral.
- `Sprint 06` exit: `make formal` passes with a real SMT solver and CI records proof results.
- `Sprint 07` next gate: integrated execution extends beyond score generation into a fuller attention command sequence.
- `Sprint 08A` exit: synthesis/elaboration evidence and debug hooks are reproducible.
- `Sprint 11A` exit: first meaningful area/timing/congestion evidence exists for `attn_core`.

Use [../templates/sprint-template.md](../templates/sprint-template.md) for future additions or replacements once the template is populated.
