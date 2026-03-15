# System Architecture

## Intent

Define the first coherent top-level architecture for an attention-focused accelerator that can eventually live inside the Caravel user project area while remaining practical for early RTL, FPGA, and OpenLane work.

## Proposed top-level blocks

```mermaid
flowchart TD
  HostCpu["Host CPU or firmware"] --> Mmio["MMIO control registers"]
  Mmio --> CmdQueue["Command queue"]
  CmdQueue --> Decoder["Tensor ISA decoder"]
  Decoder --> Scheduler["Tile scheduler"]
  Scheduler --> Dma["DMA engine"]
  Dma --> Scratchpad["Scratchpad SRAM"]
  Scratchpad --> MacArray["INT8 MAC array"]
  Scratchpad --> VectorUnit["Vector and softmax unit"]
  MacArray --> AccumPath["Accumulator path"]
  AccumPath --> Scratchpad
  VectorUnit --> Scratchpad
  Scratchpad --> Dma
```

## Baseline architectural assumptions

| Topic | Planning assumption |
| --- | --- |
| Workload | attention-oriented matrix operations with tiled execution |
| Compute | fixed-function MAC array plus helper vector path |
| Storage | software-managed scratchpad rather than fully coherent cache |
| Control | host-programmed command queue backed by MMIO control/status |
| Integration | first as stand-alone RTL/FPGA target, then Caravel-integrated accelerator |

## Dataflow model

1. Software configures control registers and submits commands.
2. The command queue feeds the ISA decoder and scheduler.
3. The DMA engine pulls tensor tiles from host-visible memory into scratchpad banks.
4. The MAC array computes score and value transforms over scheduled tiles.
5. The vector path performs helper reductions and softmax-related work.
6. Results return to scratchpad and then to host memory.

## Architectural boundaries

- The accelerator owns local scheduling and scratchpad allocation for active tiles.
- The host owns global workload sequencing, buffer preparation, and completion handling.
- The golden model remains the numerical source of truth for correctness.
- Caravel integration should preserve the same logical programming model even if bus adapters change.

## Near-term architecture outputs

- finalize the baseline precision and accumulator policy
- freeze the first tensor ISA surface
- choose scratchpad organization and double-buffering assumptions
- define the first performance model inputs and outputs

## Open questions

- How much softmax support should be hardwired versus sequenced through vector operations?
- What tile shapes best balance scratchpad usage, bus pressure, and MAC utilization on SKY130?
- Which command descriptor fields must be visible in hardware versus derived in software?
