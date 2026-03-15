# Sprint 07 - System Integration

Status: done

## Objective

Assemble the major blocks into an integrated accelerator core with a working control plane, counters, and end-to-end directed regressions.

## Deliverables

- `rtl/attn_core.sv`
- command queue and control/status register integration
- performance-counter map and first integrated measurements
- end-to-end simulation regressions against the golden model

## Dependencies

- block RTL from Sprints 03 to 05
- formal findings from Sprint 06

## Parallelization Note

Top-level assembly, software-visible control work, integrated verification, and backend smoke analysis should happen together to expose system-level issues early.

## Parallel Workstreams

### Top-level RTL lane

- compose compute, memory, vector, and control blocks into `attn_core`
- clean up cross-block handshakes and reset sequencing
- ensure debug and performance counters remain accessible

### Control-register and queue lane

- integrate command-queue management and status reporting
- define register map semantics that software can rely on
- stabilize interrupt or completion signaling strategy if used

### Integration-verification lane

- run directed end-to-end workloads through load, compute, softmax, and store sequences
- compare outputs to the golden model
- publish an integration report with known gaps and stress failures

### Software-model lane

- define a software-facing register and command model for later runtime work
- document queue programming examples
- align counter naming with future FPGA and silicon diagnostics

### Implementation-feedback lane

- run integrated lint and synthesis/OpenLane smoke checks where practical
- identify the first system-level timing and area hotspots
- feed floorplan-sensitive findings into later Caravel and physical-design planning

## Exit Criteria

- the integrated core executes at least one complete directed flow end to end
- control/status semantics are stable enough for runtime and Caravel work to begin
- first integrated performance counters and implementation observations are captured

## Evidence To Capture

- integrated RTL
- system integration report
- counter/register documentation

## Open Risks And Decisions

- top-level handshake mismatches may reveal hidden assumptions in block specs
- system-level backpressure could expose new deadlock or starvation cases
