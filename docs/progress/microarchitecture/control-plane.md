# Control Plane

## Scope

Define the instruction decoder, command queue, tile scheduler control state, completion semantics, and software-visible control/status registers.

## Control-flow sketch

1. Software configures the accelerator and posts work.
2. The command queue buffers descriptors.
3. The decoder translates commands into scheduler actions.
4. The scheduler sequences DMA, compute, and vector work.
5. Completion and error state are reflected in status registers and counters.

## Key design points

- deterministic handling of invalid or unsupported commands
- queue-empty, queue-full, and in-flight tracking semantics
- scheduler ownership of dependencies between load, compute, softmax, and store phases
- counter and debug visibility designed in from the start

## Verification intent

- decoder table tests for all supported opcodes
- queue state-machine tests covering overflow, underflow, and reset
- scheduler liveness properties and deadlock-oriented assertions
- software-visible register model tests once the runtime path exists
