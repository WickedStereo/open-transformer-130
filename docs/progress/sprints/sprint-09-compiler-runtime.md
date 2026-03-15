# Sprint 09 - Compiler and Runtime

Status: planned

## Objective

Create the software stack that lowers supported model fragments into accelerator commands and drives execution through a stable runtime interface.

## Rebaseline Note

This sprint should start with a thin-runtime path, not with a full compiler stack. The current hardware baseline is still evolving, so the immediate software need is a minimal command generator and host-side execution path that can reliably drive the integrated core. Broader graph lowering should follow only after that path is stable.

## Deliverables

- `09A`: command-buffer builder / descriptor serializer for the current ISA profile
- `09A`: minimal host-side runtime helpers for queue programming, execution, and result collection
- `09A`: runtime API notes and directed examples tied to the integrated core
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

- ISA details may still drift if control-plane integration remains unstable
- graph lowering may reveal missing hardware operations or inconvenient command granularity
- the current in-place `MATMUL` contract may be awkward for software and may need an explicit migration plan later
