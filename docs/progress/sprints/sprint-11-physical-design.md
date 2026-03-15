# Sprint 11 - Physical Design

Status: active

## Objective

Drive the integrated design through synthesis, floorplanning, place-and-route, and signoff analysis while feeding physical constraints back into the design.

## Rebaseline Note

This sprint now has two distinct layers:

- `11A`: pre-Caravel backend evidence on the integrated `attn_core` top
- `11B`: deeper physical closure once the integration target, memory macros, and packaging assumptions are more mature

The repo is already in `11A`: OpenLane targets `attn_core`, the design has an explicit SDC, and the RTL elaborates through the repo's Yosys front-end. The next step is to turn that into real timing/area/congestion evidence rather than waiting for full Caravel integration.

## Deliverables

- `11A`: updated OpenLane configuration and run strategy for `attn_core`
- `11A`: synthesis, floorplan, and early timing / congestion evidence
- `11A`: documented macro assumptions and memory-boundary implications
- `11B`: placement, routing, timing, power, DRC, and LVS reports
- `11B`: documented timing and area closure actions

## Dependencies

- integrated top from Sprint 07
- stable clock/reset assumptions and macro plan
- Caravel-integrated design from Sprint 10 for the later `11B` closure path

## Parallelization Note

Flow setup, timing analysis, physical-debug iterations, and gate-level verification should run as coordinated but partially parallel lanes.

## Parallel Workstreams

### Flow-configuration lane

- prepare OpenLane inputs, constraints, and macro placement assumptions
- stabilize repeatable run scripts and artifact locations
- capture the expected reporting package for each run
- keep `11A` runnable even before macro views and Caravel collateral are complete

### Timing-and-area lane

- analyze critical paths and utilization hotspots
- drive targeted RTL or constraint fixes when feasible
- record which issues are architectural versus implementation-specific
- separate findings caused by behavioral memories from findings likely to survive macro integration

### Memory-and-macro lane

- translate the new scratchpad wrapper boundary into backend assumptions
- define what is needed to replace behavioral memory with real SRAM macros
- capture the missing views and integration data that still block representative PPA analysis

### Signoff-debug lane

- track DRC and LVS results and triage blockers
- check power and congestion indications
- maintain a ranked closure backlog with owners
- treat full signoff closure as `11B`; do not block early feedback on it

### Verification lane

- run gate-level or post-synthesis checks where practical
- confirm that backend-introduced changes do not violate functional intent
- archive the exact design revision tied to each backend report

### Reporting lane

- publish dated reports for synthesis, timing, power, and signoff status
- summarize deltas between successive runs
- feed major lessons back into the master plan or ADRs
- make sure `11A` produces usable evidence even if the later full flow is not ready

## Exit Criteria

- `11A` exit: the project has a repeatable backend flow for `attn_core` with archived early reports
- `11A` exit: top timing, area, and congestion blockers are known and prioritized
- `11A` exit: memory/macro assumptions are explicit enough to interpret backend numbers responsibly
- full sprint exit: there is a documented path to tapeout-readiness rather than an ad hoc run history

## Evidence To Capture

- OpenLane configs and run reports
- timing, power, DRC, and LVS summaries
- closure backlog
- memory / macro assumption note tied to the backend runs

## Open Risks And Decisions

- macro placement and routing congestion may force architecture compromises
- timing fixes may interact badly with verification if not tightly controlled
- waiting for a perfect Caravel-ready target before gathering `11A` evidence would delay the most valuable ASIC feedback
