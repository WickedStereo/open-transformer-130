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

## Sprint 01 results

The performance model is implemented in [sim/performance_model.py](../../../sim/performance_model.py) and produces the following baseline outputs for the frozen 64x64 tile shape at 150 MHz with 16 MAC lanes:

| Workload | Total cycles | MAC utilization | Effective GOPS | Latency |
| --- | --- | --- | --- | --- |
| seq=128, d=64 | 135,226 | 96.9% | 2.33 | 901 us |
| seq=512, d=64 | 2,136,508 | 98.2% | 2.36 | 14,243 us |

The design is **compute-bound** across all evaluated tile sizes. DMA overlap sensitivity analysis shows that going from 0% to 100% DMA-compute overlap improves utilization by only ~5%, confirming that the memory subsystem is adequately provisioned.

These outputs serve as the reference baseline for comparison against RTL simulation results (Sprint 03+) and FPGA traces (Sprint 08).

## Deliverables

- [sim/performance_model.py](../../../sim/performance_model.py): analytical model with sweep and sensitivity functions
- [Architecture study report](../reports/2026-03-15-architecture-study.md): sweep data and decision rationale
- parameter sweep reports in [../reports/](../reports/)
- decision records when model results cause architecture changes
