# Compute Datapath

## Scope

This document defines the block-level intent for the MAC lane, MAC array, and accumulation path that implement the core tiled matrix-multiply work.

## Proposed decomposition

- `mac_lane`: operand capture, multiply, and partial-sum staging
- `mac_array`: lane coordination and tile-level data movement across lanes
- accumulation path: reduction, saturation, rounding, and writeback formatting

## Design concerns

- balancing array width against routing and clock frequency on SKY130
- choosing accumulator width and saturation behavior to match numeric studies
- minimizing control overhead between tiles so utilization remains high
- exposing just enough observability for debug without bloating the critical path

## Required interface questions

- operand valid/ready contract between scheduler and compute pipeline
- partial-sum lifetime and reset semantics
- writeback granularity into scratchpad
- stall behavior when downstream storage is not ready

## Verification intent

- deterministic unit tests for multiply, accumulate, reset, and saturation paths
- constrained-random tile traffic around valid/ready boundaries
- formal safety checks on accumulator overflow policy where feasible
- synthesis spot checks after initial RTL convergence
