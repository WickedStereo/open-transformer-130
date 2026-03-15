# Sprint 01 - Architecture Exploration

Status: planned

## Objective

Freeze the first credible architecture baseline by expanding the golden model, defining the tensor ISA, and quantifying bandwidth and utilization trade-offs.

## Deliverables

- expanded golden model for attention-oriented tiled execution
- first frozen tensor ISA draft
- performance-model definition and study results
- architecture decision package for precision, tile size, and scratchpad assumptions

## Dependencies

- Sprint 00 documentation baseline
- agreement that the current repo is still pre-RTL-implementation

## Parallelization Note

Modeling, ISA design, and performance studies should run in parallel, with a short architecture review at the end to converge on a baseline.

## Parallel Workstreams

### Modeling and numerics lane

- extend `sim/reference_attention.py` or a successor model to cover tiled execution semantics
- study precision and accumulator requirements against representative workloads
- define numeric pass/fail criteria for future RTL and FPGA comparisons

### ISA and control-model lane

- finalize the opcode set and descriptor fields for `LOAD_TILE`, `MATMUL`, `ACCUMULATE`, `SOFTMAX`, and `STORE_TILE`
- define the queue programming model and MMIO expectations
- record invalid-command behavior and reserved-field policy

### Performance-study lane

- evaluate tile-size options against scratchpad capacity and memory traffic
- estimate MAC utilization and latency sensitivity to DMA overlap assumptions
- publish an architecture study report with the chosen baseline and rejected alternatives

### Verification-planning lane

- define comparison points between the golden model and future RTL blocks
- plan scoreboard structure and required test vectors for block-level bring-up
- identify which architecture assumptions need later formal support

## Exit Criteria

- a baseline tile shape, precision policy, and control model are documented
- the ISA surface is stable enough for decoder and scheduler design
- performance-model outputs exist for the chosen baseline

## Evidence To Capture

- architecture study report
- updated architecture docs
- decision records for frozen assumptions

## Open Risks And Decisions

- architecture assumptions may be too optimistic for SKY130 area or frequency
- numeric studies may force a wider accumulator or different softmax strategy than planned
