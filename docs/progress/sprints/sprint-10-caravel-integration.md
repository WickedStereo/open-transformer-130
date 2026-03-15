# Sprint 10 - Caravel Integration

Status: planned

## Objective

Integrate the accelerator into the Caravel harness, expose a reliable host interface, and validate firmware-driven control of the design.

## Deliverables

- Caravel integration collateral and wrapper structure
- Wishbone-facing control path and register map
- firmware smoke tests for accelerator control and status
- integration notes for clocks, resets, area, and debug visibility

## Dependencies

- integrated accelerator core from Sprint 07
- software-visible control model from Sprint 09
- availability of a Caravel checkout or submodule plan

## Parallelization Note

Harness wiring, bus adaptation, firmware, and verification can proceed simultaneously once the control-plane interface is stable.

## Parallel Workstreams

### Harness-integration lane

- create the Caravel-facing wrapper and project structure needed for integration
- map clocks, resets, user area interfaces, and any logic-analyzer/debug signals
- preserve a clean separation between generic accelerator RTL and harness-specific glue

### Bus and control lane

- implement or adapt the Wishbone-facing control/register interface
- validate register accessibility, status behavior, and queue interaction
- define fault and interrupt handling semantics if needed

### Firmware lane

- write a minimal RISC-V-side driver sequence for configure, start, poll, and readback
- exercise counter reads and basic error paths
- document the firmware-visible API

### Verification lane

- build bus-level tests around register access and queue operation
- run firmware-driven smoke scenarios in simulation
- capture assumptions about external memory access and harness limitations

### Physical-awareness lane

- check that area and I/O assumptions remain compatible with the Caravel envelope
- record any pin, clock, or reset constraints that should influence backend planning
- surface integration-specific risks before physical-design work begins

## Exit Criteria

- Wishbone or equivalent Caravel host communication is functionally validated
- firmware can configure and observe the accelerator through the harness
- Caravel-specific constraints are documented before backend closure work starts

## Evidence To Capture

- Caravel wrapper collateral
- firmware smoke-test report
- integration constraint notes

## Open Risks And Decisions

- Caravel envelope and bus semantics may force control-path redesign
- integration glue can become the hidden critical path if left unmeasured
