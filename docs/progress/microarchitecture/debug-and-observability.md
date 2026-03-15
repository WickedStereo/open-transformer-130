# Debug and Observability

## Purpose

Debug infrastructure should make performance and correctness issues visible during simulation, FPGA prototyping, Caravel bring-up, and post-silicon validation.

## Planned observability features

- performance counters for busy cycles, stall cycles, MAC operations, DMA bytes, and tile completions
- status and fault registers for queue, DMA, and decode failures
- optional trace or probe points for scheduler and memory state
- firmware-readable summary registers for lab bring-up

## Design rules

- counters must be useful without perturbing the critical datapath
- debug state should be reset-clean and software-readable
- probe signals should be defined early enough to survive integration into FPGA and Caravel environments
- reports should record which counters and probes were active for a given experiment

## Planned consumers

- cocotb and regression testbenches
- FPGA logic analyzer capture
- Caravel firmware diagnostics
- post-silicon benchmark and bring-up scripts
