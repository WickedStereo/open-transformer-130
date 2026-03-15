# Sprint 04 - Memory Subsystem RTL

Status: active

## Objective

Close the memory subsystem from "functionally present" to "ASIC-relevant baseline" by validating DMA/scratchpad behavior, stabilizing the scheduler-memory contract, and establishing a credible path from behavioral memory to real SRAM macros.

## Rebaseline Note

The core RTL work for this sprint exists, but the sprint is not considered complete yet from an ASIC perspective. The remaining gap is memory realism: the design now has corrected DMA behavior and a bank-wrapper boundary, but it still needs macro-oriented collateral and backend assumptions before this sprint can truly exit.

## Deliverables

- `rtl/scratchpad.sv`
- `rtl/scratchpad_bank_1rw.sv`
- `rtl/dma_engine.sv`
- `rtl/tile_scheduler.sv`
- memory-correctness tests and scoreboards
- formal targets and harnesses for DMA / scheduler safety
- documented OpenRAM / SRAM macro integration assumptions for later ASIC migration

## Dependencies

- Sprint 02 memory-subsystem spec
- baseline address and tile-shape conventions from Sprint 01

## Parallelization Note

Scratchpad, DMA, scheduler, and memory-verification work can proceed in parallel if interface contracts are respected.

## Parallel Workstreams

### Scratchpad RTL lane

- implement the banked storage abstraction and address decode
- define read/write collision behavior and bank arbitration
- leave a clean path for future OpenRAM-backed replacement through a bank wrapper boundary

### DMA RTL lane

- implement request sequencing, transfer tracking, and completion signaling
- surface error conditions and byte counters
- align the DMA control path with the documented 1-cycle scratchpad read latency
- document the queued-DMA host-addressing profile used by the current integrated core

### Scheduler RTL lane

- track tile residency and dependency readiness
- sequence DMA and compute ownership cleanly
- define recovery behavior for faults or stalled resources
- keep the software-visible memory contract simple enough for early runtime work

### Verification and formal lane

- build scoreboards for memory movement correctness
- write initial properties for bounds checking and deadlock avoidance
- stress arbitration and backpressure corner cases
- keep standalone DMA / scheduler benches runnable as regression evidence

### Memory-macro planning lane

- translate the scratchpad assumptions into OpenRAM requirements
- record banking, aspect-ratio, and port assumptions
- flag choices that may complicate macro integration later
- define what collateral is still missing: macro configs, LEF/lib views, black-box integration notes, and replacement plan

## Exit Criteria

- tile movement into and out of scratchpad is functionally validated under the current arbiter/scratchpad timing model
- DMA load and store behavior are covered by standalone regression evidence
- DMA safety and scheduler-liveness targets are explicitly tracked
- the scratchpad sits behind a stable macro-oriented wrapper boundary
- the project has a documented path from behavioral memories to generated macros

## Evidence To Capture

- memory-subsystem RTL
- memory and DMA verification report
- OpenRAM planning note, ADR, or equivalent macro integration note
- backend-facing note describing memory assumptions carried into synthesis / floorplanning

## Open Risks And Decisions

- memory arbitration could become the dominant stall source
- scratchpad organization may need revision once macro realities are known
- the current serialized scratchpad access model may understate the eventual pressure from macro timing and porting constraints
