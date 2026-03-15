# Sprint 09 - Compiler and Runtime

Status: planned

## Objective

Create the software stack that lowers supported model fragments into accelerator commands and drives execution through a stable runtime interface.

## Deliverables

- `compiler/lowering.py`
- `compiler/onnx_to_tile.py`
- command-buffer schema and runtime API notes
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

### Command-emission lane

- serialize command buffers or descriptors according to the frozen ISA
- track buffer layout, alignment, and metadata needs
- keep the format compatible with both simulation and future Caravel firmware paths

### Runtime lane

- define host-side APIs for loading buffers, queueing work, and collecting results
- prepare a minimal driver model for later firmware reuse
- document error handling and timeout behavior

### Verification lane

- compare compiler outputs to the golden model and command-level expectations
- run end-to-end tests through simulation and, when available, FPGA
- publish supported-model and known-gap documentation

## Exit Criteria

- a supported model fragment lowers end to end into accelerator commands
- runtime semantics are documented and testable
- compiler outputs are validated against the numerical reference

## Evidence To Capture

- compiler and runtime source files
- compiler validation report
- supported-op matrix

## Open Risks And Decisions

- ISA details may still drift if control-plane integration remains unstable
- graph lowering may reveal missing hardware operations or inconvenient command granularity
