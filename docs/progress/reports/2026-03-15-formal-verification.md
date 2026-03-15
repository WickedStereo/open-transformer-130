# Formal Verification Report

Date: 2026-03-15
Sprint: 06

## Summary

SVA property suites and SymbiYosys configuration files have been created for four critical blocks. Property modules can be bound to DUT instances for formal proof or used as simulation-time assertions via cocotb/Verilator.

## Property inventory

### mac_lane_props (4 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | Accumulator is zero after reset | Written |
| P2 | Safety | Accumulator always in INT32 range | Written |
| P3 | Cover | lane_busy drains within 3 idle cycles | Written |
| P4 | Safety | accum_clear produces product-only result | Documented |

### dma_engine_props (5 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | DMA requests at most one bank per cycle | Written |
| P2 | Safety | cmd_ready only in IDLE state | Written |
| P3 | Safety | done and error are mutually exclusive | Written |
| P4 | Safety | done is a one-cycle pulse | Written |
| P5 | Liveness | Every accepted command completes | Cover |

### isa_decoder_props (6 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | Invalid opcode produces fault | Written |
| P2 | Safety | Nonzero reserved field produces fault | Written |
| P3 | Safety | fault_active blocks new decodes | Written |
| P4 | Safety | fault_clear deasserts fault_active | Written |
| P5 | Safety | desc_consumed is a one-cycle pulse | Written |
| P6 | Safety | Valid opcode produces action (no fault) | Written |

### tile_scheduler_props (5 properties)

| ID | Type | Description | Status |
| --- | --- | --- | --- |
| P1 | Safety | At most one command type per cycle | Written |
| P2 | Safety | action_ready only when IDLE and enabled | Written |
| P3 | Safety | Slot state transitions are valid | Documented |
| P4 | Safety | busy matches non-IDLE state | Documented |
| P5 | Liveness | No permanent busy (deadlock freedom) | Cover |

## Formal tool status

- **Yosys**: Available (synthesis and SMT2 export)
- **SymbiYosys**: Not installed in current environment
- **Z3/Boolector**: Not verified

SymbiYosys `.sby` configuration files are ready in `formal/`. Properties are encoded as standard SVA and can be:
1. Bound to DUT instances and proven with `sby` when available
2. Checked during Verilator simulation (subset of SVA supported)
3. Verified manually against cocotb test coverage

## Assumptions

- All properties assume synchronous reset (`rst_n` active low)
- Liveness properties use bounded depths (20–100 cycles)
- Slot state transition properties assume well-formed scheduler FSM

## Counterexamples and gaps

- No counterexamples found in simulation-based checking
- Unbounded liveness proofs require SymbiYosys with an SMT solver
- Slot state transition validity (P3 in scheduler) needs elaboration once integration tests run

## CI integration plan

When SymbiYosys becomes available:
1. Add `make formal` target running `.sby` files
2. Gate safety properties (fail CI on counterexample)
3. Run cover properties as informational (no CI gate)
