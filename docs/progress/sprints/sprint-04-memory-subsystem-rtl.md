# Sprint 04 - Memory Subsystem RTL

Status: planned

## Objective

Implement the scratchpad, DMA, and memory-facing scheduler behavior needed to move and stage tiles safely and efficiently.

## Deliverables

- `rtl/scratchpad.sv`
- `rtl/dma_engine.sv`
- `rtl/tile_scheduler.sv`
- memory-correctness tests and formal target list
- OpenRAM planning notes for later ASIC migration

## Dependencies

- Sprint 02 memory-subsystem spec
- baseline address and tile-shape conventions from Sprint 01

## Parallelization Note

Scratchpad, DMA, scheduler, and memory-verification work can proceed in parallel if interface contracts are respected.

## Parallel Workstreams

### Scratchpad RTL lane

- implement the banked storage abstraction and address decode
- define read/write collision behavior and bank arbitration
- leave a clean path for future OpenRAM-backed replacement

### DMA RTL lane

- implement request sequencing, transfer tracking, and completion signaling
- surface error conditions and byte counters
- align the DMA control path with future Caravel-facing memory access constraints

### Scheduler RTL lane

- track tile residency and dependency readiness
- sequence DMA and compute ownership cleanly
- define recovery behavior for faults or stalled resources

### Verification and formal lane

- build scoreboards for memory movement correctness
- write initial properties for bounds checking and deadlock avoidance
- stress arbitration and backpressure corner cases

### Memory-macro planning lane

- translate the scratchpad assumptions into OpenRAM requirements
- record banking, aspect-ratio, and port assumptions
- flag choices that may complicate macro integration later

## Exit Criteria

- tile movement into and out of scratchpad is functionally validated
- DMA safety and scheduler-liveness targets are explicitly tracked
- the project has a documented path from behavioral memories to generated macros

## Evidence To Capture

- memory-subsystem RTL
- memory and DMA verification report
- OpenRAM planning note or ADR

## Open Risks And Decisions

- memory arbitration could become the dominant stall source
- scratchpad organization may need revision once macro realities are known
