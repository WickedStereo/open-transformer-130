# Sprint 08 - FPGA Prototype

Status: active

## Objective

Build an FPGA implementation path that supports real workload execution, observability, and faster architectural iteration than RTL simulation alone.

## Rebaseline Note

This sprint is now split conceptually into two layers:

- `08A`: synthesis / elaboration / debugability evidence on the integrated `attn_core` top
- `08B`: board-specific wrapper, constraints, and demonstrable FPGA bring-up

The repo has already entered `08A` because the integrated top now elaborates through the Yosys front-end and the Makefile defaults to `attn_core`. The board-specific portion is still future work.

## Deliverables

- `08A`: repeatable synthesis / elaboration collateral for `attn_core`
- `08A`: debug probes, counters, and trace-capture requirements for faster bring-up
- `08B`: board-specific wrapper, constraints, and build collateral under `fpga/`
- `08B`: BRAM-backed adaptation of the scratchpad path where needed
- `08B`: FPGA demo workload and run report

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
- treat this as `08B`, not as a blocker for early synthesis/debug evidence

### Memory-adaptation lane

- replace or wrap scratchpad storage with FPGA-friendly BRAM resources
- document behavioral differences versus the ASIC path
- measure any bandwidth or latency changes caused by the adaptation
- keep the ASIC memory contract visible so FPGA convenience changes do not silently redefine the architecture

### Runtime and demo lane

- prepare a minimal workload-loading and result-readback path
- run at least one demonstrable attention-oriented workload
- capture throughput and correctness data
- start with debug-friendly directed sequences before chasing bigger demos

### Instrumentation lane

- surface counters and probe points through FPGA-observable paths
- capture traces around stalls, queue behavior, and memory traffic
- turn recurring debug needs into permanent observability requirements
- make `08A` useful even before a board wrapper exists by improving synthesis/debug visibility

## Exit Criteria

- `08A` exit: synthesis/elaboration evidence is reproducible for `attn_core`, and the required observability hooks are identified
- full sprint exit: the FPGA image builds and runs a directed workload
- correctness is checked against the golden model or simulation reference
- at least one performance or debug report is captured from the prototype

## Evidence To Capture

- synthesis / elaboration logs and reports for the integrated top
- FPGA wrapper and constraints
- prototype run report
- captured traces or counter summaries

## Open Risks And Decisions

- board-resource limits may force compromises not representative of ASIC intent
- the FPGA adaptation can mask or create memory-system behaviors that differ from the final chip
- spending too long on `08B` before collecting `08A` evidence can delay useful architectural feedback
