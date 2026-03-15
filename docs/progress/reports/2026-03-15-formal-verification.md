# Formal Verification Report

Date: 2026-03-15
Sprint: 06

## Summary

Local solver-backed proofs now run end to end via `make formal`. The repository now defaults to `cvc4`, which closes the current `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler` suites in practical runtime.

Proof closure required real triage rather than just tool installation. Several early counterexamples were caused by reset-history sampling and registered-output timing mismatches in the property files, especially around decoder fault latching and `desc_consumed` timing. Those properties were rewritten to match the RTL contract instead of assuming combinational behavior that the design does not provide.

## Local result summary

| Target | Solver | Bound | Result | Notes |
| --- | --- | --- | --- | --- |
| `mac_lane` | `cvc4` | 20 | Passed | Safety assertions proven locally; idle-drain remains a cover point |
| `isa_decoder` | `cvc4` | 20 | Passed | Properties now model reset gating, fault-latch timing, and registered consume behavior |
| `dma_engine` | `cvc4` | 6 | Passed | Bounded safety run; valid accepted commands are constrained to small transfers for tractability |
| `tile_scheduler` | `cvc4` | 30 | Passed | Safety assertions proven locally; deadlock freedom remains a cover-oriented bounded check |

## Property inventory

### mac_lane_props (4 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | Accumulator is zero after reset | Proven locally |
| P2 | Safety | Accumulator always in INT32 range | Proven locally |
| P3 | Cover | lane_busy drains within 3 idle cycles | Cover only |
| P4 | Safety | accum_clear produces product-only result | Documented only |

### dma_engine_props (5 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | DMA requests at most one bank per cycle | Proven locally |
| P2 | Safety | cmd_ready only in IDLE state | Proven locally |
| P3 | Safety | done and error are mutually exclusive | Proven locally |
| P4 | Safety | done is a one-cycle pulse | Proven locally |
| P5 | Liveness | Every accepted command completes | Cover only |

### isa_decoder_props (6 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | Invalid opcode presented while idle produces fault | Proven locally |
| P2 | Safety | Nonzero reserved field presented while idle produces fault | Proven locally |
| P3 | Safety | Latched fault state blocks new decodes after latch takes effect | Proven locally |
| P4 | Safety | `fault_clear` deasserts `fault_active` | Proven locally |
| P5 | Safety | `desc_consumed` corresponds to a fault consume or prior action handshake | Proven locally |
| P6 | Safety | Valid opcode presented while idle produces an action without faulting | Proven locally |

### tile_scheduler_props (5 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | At most one command type per cycle | Proven locally |
| P2 | Safety | action_ready only when IDLE and enabled | Proven locally |
| P3 | Safety | Slot state transitions are valid | Documented only |
| P4 | Safety | busy matches non-IDLE state | Documented only |
| P5 | Liveness | No permanent busy (deadlock freedom) | Cover only |

## Formal tool status

- **Yosys**: Available (synthesis and SMT2 export)
- **SymbiYosys**: Not installed in current environment
- **cvc4**: Installed and now the default `FORMAL_SOLVER`
- **z3**: Installed, but substantially slower on the current decoder proof in this environment, so it is no longer the default local engine

SymbiYosys `.sby` configuration files remain in `formal/`, but the actively maintained proof flow today is the direct `yosys-smtbmc` path behind `make formal`.

## Assumptions

- All properties assume synchronous reset (`rst_n` active low)
- Past-based assertions are gated so reset cycles do not create spurious obligations from unconstrained pre-reset state
- `dma_engine_formal` models immediate bus acknowledgements and scratch grants, and constrains accepted valid commands to `<= 8` bytes so the bounded DMA proof stays tractable
- The current bounded depths are `20` for `mac_lane`, `20` for `isa_decoder`, `6` for `dma_engine`, and `30` for `tile_scheduler`
- Liveness / deadlock statements remain bounded cover checks rather than unbounded proofs
- Slot-state transition validity in `tile_scheduler` is still documented rather than fully encoded as assertions

## Counterexamples and gaps

- Initial counterexamples in `mac_lane`, `isa_decoder`, and `dma_engine` were triaged into property/harness fixes around reset sampling and registered-output timing
- Decoder properties now explicitly model idle gating, delayed fault latching, and the fact that `desc_consumed` reflects a prior action handshake in the non-fault path
- No surviving safety counterexamples remain in the current bounded local suite
- Unbounded liveness proofs and deeper DMA transfer proofs remain future work that would benefit from a SymbiYosys-based flow or a more specialized proof decomposition
- Scheduler slot-transition and busy-state semantic checks are still only partially encoded

## CI integration status

1. GitHub Actions now installs `cvc4` in addition to the existing toolchain prerequisites.
2. CI runs `make formal`, which executes the same bounded proof suite used locally.
3. Future formal expansion should add separate non-gating jobs for deeper cover runs or SymbiYosys-backed unbounded proofs rather than overloading the current safety gate.
