# Sprint 06 - Formal Verification

Status: planned

## Objective

Introduce a formal verification flow that proves critical safety and liveness properties for the core control and memory blocks.

## Deliverables

- SymbiYosys setup and reusable proof harness structure
- property suites for DMA, decoder, accumulator policy, and scheduler
- formal regression strategy and results report
- triaged counterexample backlog for any unproven properties

## Dependencies

- core block RTL from Sprints 03 to 05
- microarchitecture property targets from Sprint 02

## Parallelization Note

Formal infrastructure and module-specific proof work can proceed in parallel across block owners.

## Parallel Workstreams

### Formal-infrastructure lane

- set up the SymbiYosys directory structure, scripts, and conventions
- define common assumptions and helper modules
- document how proofs will be run locally and in CI

### DMA and memory-properties lane

- prove no invalid memory access is issued under the modeled assumptions
- check bounds, completion, and handshake safety
- capture assumptions that still require simulation-based confidence

### Decoder and scheduler-properties lane

- prove deterministic invalid-opcode handling
- target no-deadlock or progress properties for the scheduler
- check queue-state invariants and reset behavior

### Accumulator-properties lane

- prove or bound the selected overflow policy
- check reset and accumulation invariants
- record any cases where wider arithmetic would simplify proofs

### Reporting and CI lane

- summarize proofs, bounds, assumptions, and failures in a dated report
- decide which proofs are gating versus informational
- wire stable proofs into CI over time

## Exit Criteria

- critical safety properties are proven or bounded with documented assumptions
- counterexamples are triaged into fixes, assumptions, or accepted limitations
- the team has a repeatable formal workflow rather than one-off experiments

## Evidence To Capture

- formal harnesses and property files
- formal verification report
- CI integration notes

## Open Risks And Decisions

- overly aggressive assumptions can hide real bugs
- late interface churn can invalidate proofs and waste effort
