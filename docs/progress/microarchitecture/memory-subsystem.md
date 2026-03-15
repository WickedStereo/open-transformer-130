# Memory Subsystem

## Scope

Cover the scratchpad, DMA engine, and memory-facing portions of the tile scheduler.

## Proposed responsibilities

- scratchpad: banked storage, port arbitration, and address decode
- DMA engine: host-memory transfer sequencing, bounds checking, and completion signaling
- scheduler memory side: tile residency tracking, buffer reuse, and hazard avoidance

## Key contracts

- software-visible tile identifiers map deterministically to scratchpad regions
- DMA completion status is visible to both scheduler logic and software
- conflicting accesses must resolve with defined priority or backpressure semantics
- error conditions must surface through status registers and debug counters

## Formal targets

- no invalid memory-access issue by DMA
- no scheduler deadlock due to wait conditions
- no scratchpad bank select outside legal range

## Reporting expectations

Each implementation milestone should publish bytes moved, stall reasons, arbitration corner cases, and any assumptions that remain unproven.
