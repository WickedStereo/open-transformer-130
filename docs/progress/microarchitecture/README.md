# Microarchitecture Documents

This directory holds block-level specifications that refine the system architecture into implementable RTL units. All specs frozen in Sprint 02.

Block specifications:

- [Compute Datapath](compute-datapath.md) -- mac_lane, mac_array, accumulator writeback
- [Memory Subsystem](memory-subsystem.md) -- scratchpad, bank arbiter, DMA engine, tile residency
- [Control Plane](control-plane.md) -- decoder, queue controller, tile scheduler, MMIO registers
- [Vector and Softmax](vector-softmax.md) -- softmax pipeline, exp approximation, reduction stages
- [Debug and Observability](debug-and-observability.md) -- performance counters, probes, FPGA/Caravel mapping

Cross-cutting documents:

- [Block Interface Definitions](interfaces.md) -- signal-level interface tables between all blocks
- [Physical Awareness Notes](physical-awareness.md) -- area, clock, reset, SKY130 constraints
