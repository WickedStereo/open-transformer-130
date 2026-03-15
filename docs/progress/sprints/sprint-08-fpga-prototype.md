# Sprint 08 - FPGA Prototype

Status: planned

## Objective

Build an FPGA implementation path that supports real workload execution, observability, and faster architectural iteration than RTL simulation alone.

## Deliverables

- board-specific wrapper, constraints, and build collateral under `fpga/`
- BRAM-backed adaptation of the scratchpad path
- debug probes and trace capture hooks
- FPGA demo workload and run report

## Dependencies

- integrated core from Sprint 07
- board selection and FPGA-memory assumptions

## Parallelization Note

Wrapper development, BRAM adaptation, host/runtime plumbing, and instrumentation can progress in parallel once the integrated RTL exists.

## Parallel Workstreams

### FPGA-wrapper lane

- create the board-specific top level and constraints
- map clocks, resets, and any I/O needed for a demo path
- keep the wrapper isolated from the ASIC top-level design where possible

### Memory-adaptation lane

- replace or wrap scratchpad storage with FPGA-friendly BRAM resources
- document behavioral differences versus the ASIC path
- measure any bandwidth or latency changes caused by the adaptation

### Runtime and demo lane

- prepare a minimal workload-loading and result-readback path
- run at least one demonstrable attention-oriented workload
- capture throughput and correctness data

### Instrumentation lane

- surface counters and probe points through FPGA-observable paths
- capture traces around stalls, queue behavior, and memory traffic
- turn recurring debug needs into permanent observability requirements

## Exit Criteria

- the FPGA image builds and runs a directed workload
- correctness is checked against the golden model or simulation reference
- at least one performance or debug report is captured from the prototype

## Evidence To Capture

- FPGA wrapper and constraints
- prototype run report
- captured traces or counter summaries

## Open Risks And Decisions

- board-resource limits may force compromises not representative of ASIC intent
- the FPGA adaptation can mask or create memory-system behaviors that differ from the final chip
