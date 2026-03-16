# Sprint 06 - Formal Verification

Status: done (bounded `cvc4` suite green)

## Objective

Convert the repo's formal collateral from attached harnesses and local elaboration checks into solver-backed proof evidence for the most critical safety and bounded-progress properties.

## Rebaseline Note

This sprint is no longer about creating the formal skeleton. That exists. The current non-ASIC close-out work is complete for the bounded local flow: `make formal` passes with `cvc4` across `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`, and the archived report now reflects the final harness assumptions and bounds.

The highest-risk closure item was the scheduler proof. It now models the sequential slot-state behavior more faithfully, uses a reduced 4-slot harness for tractability, constrains valid action opcodes, and checks issue/completion sequencing without assuming combinational updates that the RTL does not implement.

## Deliverables

- SymbiYosys / `make formal` setup and reusable proof harness structure
- property suites for DMA, decoder, accumulator policy, and scheduler
- solver-backed proof runs and archived results
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
- standardize solver/tool versions so results are reproducible

### DMA and memory-properties lane

- prove no invalid memory access is issued under the modeled assumptions
- check bounds, completion, and handshake safety
- capture assumptions that still require simulation-based confidence

### Decoder and scheduler-properties lane

- prove deterministic invalid-opcode handling
- target no-deadlock or progress properties for the scheduler
- check queue-state invariants and reset behavior
- keep bounded liveness properties explicit about the limits of the proof model

### Accumulator-properties lane

- prove or bound the selected overflow policy
- check reset and accumulation invariants
- record any cases where wider arithmetic would simplify proofs

### Reporting and CI lane

- summarize proofs, bounds, assumptions, and failures in a dated report
- decide which proofs are gating versus informational
- wire stable proofs into CI as a required step
- record solver/version information alongside proof results

## Exit Criteria

- `make formal` runs end to end with a real SMT solver
- critical safety properties are proven or bounded with documented assumptions
- counterexamples are triaged into fixes, assumptions, or accepted limitations
- CI records proof execution as evidence rather than only carrying placeholder setup
- the team has a repeatable formal workflow rather than one-off experiments

## Evidence To Capture

- formal harnesses and property files
- formal verification report
- CI integration notes
- proof logs or summarized result artifacts tied to a solver/tool version

## Open Risks And Decisions

- the current proof set is still bounded; deeper DMA lengths and unbounded liveness remain follow-on work if scope expands
- the scheduler closure depends on a reduced 4-slot harness and constrained opcode space, which is appropriate for the current safety gate but not a proof of the full 32-slot state space
- tool-version drift can still make a "working" formal flow look healthy locally while failing in CI
