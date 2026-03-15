# Memory Hierarchy

## Hierarchy overview

The planned hierarchy is intentionally software-managed:

`Host memory -> DMA engine -> scratchpad SRAM -> compute units -> scratchpad SRAM -> DMA engine -> host memory`

This reduces the complexity of coherence and cache behavior while making data movement visible to both the performance model and the verification plan.

## Scratchpad intent

- Target capacity class: 128 KiB, refined by architecture studies and macro availability.
- Organization: banked storage sized to support concurrent DMA and compute accesses.
- Usage model: double buffering where possible so one tile set is loaded while another is consumed.
- Implementation path: behavioral memories during early RTL, OpenRAM-backed macros during ASIC integration.

## DMA responsibilities

- fetch tiles from host-visible memory
- handle aligned burst-style transfers where practical
- enforce bounds and queue ordering guarantees
- expose error status and byte counters for debug

## Memory-centric design questions

- bank count versus routing complexity
- scratchpad addressing scheme exposed to software
- arbitration between MAC array, vector unit, and DMA
- whether softmax temporaries reside fully in scratchpad or partially in local line buffers

## Verification hooks

- scoreboard for host-memory to scratchpad correctness
- assertions for no out-of-range bank access
- backpressure tests across DMA and scheduler boundaries
- reportable counters for bytes moved, bank conflicts, and idle cycles
