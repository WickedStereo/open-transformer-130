# Performance Model

## Purpose

The performance model prevents avoidable architecture mistakes by quantifying utilization, bandwidth pressure, and predicted throughput before large RTL investment.

## Required inputs

- tile dimensions
- operand precision and accumulator width
- scratchpad capacity and bank topology assumptions
- host-memory bandwidth assumption
- MAC lane count and pipeline latency
- scheduler overhead and DMA overlap assumptions

## Required outputs

- tokens per second
- effective GOPS
- MAC utilization
- latency per layer or kernel sequence
- DMA traffic volume and peak bandwidth demand
- stall breakdown by memory, control, and compute causes

## First-order equations

A first pass should estimate:

- compute time from total MAC operations divided by active MAC throughput
- transfer time from bytes moved divided by sustainable bandwidth
- effective latency as the maximum of overlapped stages plus non-overlapped control overhead
- utilization as useful MAC cycles divided by provisioned MAC cycles

## Planned validation loop

- compare model predictions against directed RTL simulations once unit blocks exist
- compare model predictions against FPGA traces after the prototype path is alive
- compare model assumptions against OpenLane timing and area constraints before tapeout freeze

## Deliverables

- architecture study notebooks or scripts in `sim/` or `compiler/`
- parameter sweep reports in [../reports/](../reports/)
- decision records when model results cause architecture changes
