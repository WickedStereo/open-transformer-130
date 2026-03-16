# Sprint 09 - Compiler and Runtime

Status: done (runtime + lowering baseline)

## Objective

Create the software stack that lowers supported model fragments into accelerator commands and drives execution through a stable runtime interface.

## Rebaseline Note

This sprint started with the thin-runtime path and now has a working baseline implementation. The repository includes a host-side runtime for MMIO / queue programming, descriptor serialization, staged host-memory images, attention lowering helpers, and ONNX subgraph extraction for the currently supported `MatMul -> Softmax -> MatMul` pattern. Broader compiler ambition remains future work, but the first software-visible execution path is no longer missing.

## Deliverables

- `09A`: command-buffer builder / descriptor serializer for the current ISA profile
- `09A`: minimal host-side runtime helpers for queue programming, execution, and result collection
- `09A`: runtime API notes captured in `software/runtime.py`
- `09B`: `compiler/lowering.py`
- `09B`: `compiler/onnx_to_tile.py`
- lowering tests against the golden model and accelerator command semantics

## Dependencies

- integrated command model from Sprint 07
- architecture and ISA freeze from Sprint 01

## Parallelization Note

Graph lowering, command emission, runtime work, and verification can advance together once the software-visible control surface is stable.

## Parallel Workstreams

### Lowering lane

- map supported ONNX or intermediate operations into tiled accelerator commands
- define how attention subgraphs are partitioned across hardware and software
- record unsupported patterns explicitly
- treat this as follow-on `09B` work rather than the first blocker

### Command-emission lane

- serialize command buffers or descriptors according to the frozen ISA
- track buffer layout, alignment, and metadata needs
- keep the format compatible with both simulation and future Caravel firmware paths
- start from the currently implemented integrated profile, even if it is narrower than the final target programming model

### Runtime lane

- define host-side APIs for loading buffers, queueing work, and collecting results
- prepare a minimal driver model for later firmware reuse
- document error handling and timeout behavior
- prioritize a debug-friendly bring-up layer over abstraction depth

### Verification lane

- compare compiler outputs to the golden model and command-level expectations
- run end-to-end tests through simulation and, when available, FPGA
- publish supported-model and known-gap documentation
- make the first success criterion "software can drive the current integrated workload" before targeting broader model coverage

## Exit Criteria

- `09A` exit: software can build and submit the current integrated command sequence without hand-written descriptors
- runtime semantics are documented and testable
- full sprint exit: a supported model fragment lowers end to end into accelerator commands
- compiler outputs are validated against the numerical reference

## Evidence To Capture

- command-builder / runtime source files
- compiler validation report
- supported-op matrix
- directed programming examples for the integrated core

## Open Risks And Decisions

- graph lowering currently targets only the repo's supported single-tile attention fragment and rank-2 ONNX tensors
- future software work will likely need a broader buffer/tensor model once multi-tile scheduling exists
- the current in-place `MATMUL` contract may still prove awkward for wider software adoption and may need an explicit migration plan later
