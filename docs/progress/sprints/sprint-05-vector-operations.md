# Sprint 05 - Vector Operations

Status: planned

## Objective

Implement the vector helper path, softmax strategy, and decoder logic needed to support attention normalization and command execution.

## Deliverables

- `rtl/vector_unit.sv`
- `rtl/softmax.sv`
- `rtl/isa_decoder.sv`
- softmax numeric-error characterization
- decoder test plan and opcode coverage summary

## Dependencies

- Sprint 01 ISA decisions
- Sprint 02 vector/control microarchitecture

## Parallelization Note

Softmax numerics, decoder implementation, and vector RTL can progress together if the opcode surface is already frozen.

## Parallel Workstreams

### Vector-math RTL lane

- implement elementwise helper operations needed by the command set
- define interfaces to scratchpad and scheduler control
- bound latency and backpressure behavior clearly

### Softmax study and RTL lane

- select the approximation strategy and encode its control knobs
- implement the reduction and normalization path
- publish bounded-error data against the golden model

### Decoder lane

- map command descriptors into internal control signals
- handle invalid opcodes and reserved fields deterministically
- stabilize status and fault reporting for software visibility

### Verification and formal lane

- test softmax edge cases and approximation bounds
- test opcode decode coverage and invalid-command behavior
- write any lightweight properties needed for decoder safety or control consistency

## Exit Criteria

- vector and decoder blocks pass their directed verification goals
- softmax error bounds are documented and accepted
- the control surface is stable enough for top-level integration

## Evidence To Capture

- vector, softmax, and decoder RTL
- numeric-error report
- opcode coverage summary

## Open Risks And Decisions

- softmax accuracy targets may conflict with hardware simplicity
- decoder complexity can leak into scheduler timing if interfaces are not kept clean
