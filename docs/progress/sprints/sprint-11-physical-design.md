# Sprint 11 - Physical Design

Status: planned

## Objective

Drive the integrated design through synthesis, floorplanning, place-and-route, and signoff analysis while feeding physical constraints back into the design.

## Deliverables

- updated OpenLane configuration and run strategy
- synthesis, floorplan, placement, routing, timing, and power reports
- DRC and LVS status with ranked issue list
- documented timing and area closure actions

## Dependencies

- Caravel-integrated design from Sprint 10
- stable clock/reset assumptions and macro plan

## Parallelization Note

Flow setup, timing analysis, physical-debug iterations, and gate-level verification should run as coordinated but partially parallel lanes.

## Parallel Workstreams

### Flow-configuration lane

- prepare OpenLane inputs, constraints, and macro placement assumptions
- stabilize repeatable run scripts and artifact locations
- capture the expected reporting package for each run

### Timing-and-area lane

- analyze critical paths and utilization hotspots
- drive targeted RTL or constraint fixes when feasible
- record which issues are architectural versus implementation-specific

### Signoff-debug lane

- track DRC and LVS results and triage blockers
- check power and congestion indications
- maintain a ranked closure backlog with owners

### Verification lane

- run gate-level or post-synthesis checks where practical
- confirm that backend-introduced changes do not violate functional intent
- archive the exact design revision tied to each backend report

### Reporting lane

- publish dated reports for synthesis, timing, power, and signoff status
- summarize deltas between successive runs
- feed major lessons back into the master plan or ADRs

## Exit Criteria

- the project has a repeatable backend flow with archived reports
- top timing, area, and signoff blockers are known and prioritized
- there is a documented path to tapeout-readiness rather than an ad hoc run history

## Evidence To Capture

- OpenLane configs and run reports
- timing, power, DRC, and LVS summaries
- closure backlog

## Open Risks And Decisions

- macro placement and routing congestion may force architecture compromises
- timing fixes may interact badly with verification if not tightly controlled
