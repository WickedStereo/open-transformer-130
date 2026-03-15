# Master Plan

## Mission

Deliver an open hardware transformer attention accelerator that can progress from architectural exploration to RTL, FPGA validation, Caravel integration, SKY130 physical implementation, tapeout, and post-silicon benchmarking.

This plan is anchored to the actual repository baseline documented in [Current State](current-state.md). The roadmap is intentionally ambitious, but each phase is written so progress can be measured with artifacts, reports, and verification evidence rather than intuition.

## Program principles

- Keep architecture work ahead of RTL so implementation follows measured decisions.
- Treat verification, formal, FPGA, and physical design as first-class workstreams rather than end-stage cleanup.
- Preserve reproducibility through the existing containerized environment and command entrypoints in [Makefile](../../Makefile).
- Separate current implementation truth from target architecture intent.

## Target baseline to validate in Sprint 1

| Parameter | Initial target |
| --- | --- |
| Data type | INT8 operands |
| Accumulator | INT16 or wider internal accumulation, finalized after numeric study |
| Compute organization | Tiled matrix-multiply engine optimized for attention |
| Scratchpad | 128 KiB class on-chip storage target |
| Tile shape | 64 x 64 baseline candidate |
| Control model | MMIO-configured command queue with tensor ISA |
| Performance target | Approximate 150 MHz class clock target on SKY130, refined after synthesis studies |

These values are planning anchors, not frozen commitments, until architecture exploration completes.

## End-to-end phase flow

```mermaid
flowchart TD
  sprint0["Sprint 0: Bootstrap"] --> sprint1["Sprint 1: Architecture Exploration"]
  sprint1 --> sprint2["Sprint 2: Microarchitecture"]
  sprint2 --> sprint3["Sprint 3: MAC Array RTL"]
  sprint2 --> sprint4["Sprint 4: Memory Subsystem RTL"]
  sprint2 --> sprint5["Sprint 5: Vector Operations"]
  sprint3 --> sprint6["Sprint 6: Formal Verification"]
  sprint4 --> sprint6
  sprint5 --> sprint6
  sprint3 --> sprint7["Sprint 7: System Integration"]
  sprint4 --> sprint7
  sprint5 --> sprint7
  sprint6 --> sprint7
  sprint7 --> sprint8["Sprint 8: FPGA Prototype"]
  sprint7 --> sprint9["Sprint 9: Compiler and Runtime"]
  sprint7 --> sprint10["Sprint 10: Caravel Integration"]
  sprint10 --> sprint11["Sprint 11: Physical Design"]
  sprint11 --> sprint12["Sprint 12: Tapeout Preparation"]
  sprint12 --> sprint13["Sprint 13: Post-Silicon Validation"]
  sprint8 --> sprint13
  sprint9 --> sprint13
```

## Phase summary

| Sprint | Theme | Primary outputs | Main dependency |
| --- | --- | --- | --- |
| [Sprint 00](sprints/sprint-00-bootstrap.md) | Repository bootstrap | docs structure, environment checks, CI expectations, baseline reports | current scaffold |
| [Sprint 01](sprints/sprint-01-architecture-exploration.md) | Architecture exploration | golden model expansion, tensor ISA, performance model, architecture freeze proposal | bootstrap evidence |
| [Sprint 02](sprints/sprint-02-microarchitecture.md) | Microarchitecture | block specs, interfaces, buffering plan, verification plan | architecture decisions |
| [Sprint 03](sprints/sprint-03-mac-array-rtl.md) | MAC RTL | lane and array RTL, unit tests, synthesis data | microarchitecture freeze |
| [Sprint 04](sprints/sprint-04-memory-subsystem-rtl.md) | Memory RTL | scratchpad, DMA, tile scheduler RTL | microarchitecture freeze |
| [Sprint 05](sprints/sprint-05-vector-operations.md) | Vector and softmax RTL | vector operations, softmax path, decoder logic | microarchitecture freeze |
| [Sprint 06](sprints/sprint-06-formal-verification.md) | Formal | property suites, proof harnesses, formal CI integration | core blocks implemented |
| [Sprint 07](sprints/sprint-07-system-integration.md) | Integration | `attn_core`, control plane, counters, end-to-end regressions | blocks + formal lessons |
| [Sprint 08](sprints/sprint-08-fpga-prototype.md) | FPGA | board wrapper, BRAM mapping, debug traces, demo workload | integrated core |
| [Sprint 09](sprints/sprint-09-compiler-runtime.md) | Compiler/runtime | lowering path, command generation, software driver model | integrated core |
| [Sprint 10](sprints/sprint-10-caravel-integration.md) | Caravel | wrapper, Wishbone interface, firmware tests, integration collateral | integrated core |
| [Sprint 11](sprints/sprint-11-physical-design.md) | Physical design | synthesis, floorplan, PnR, timing, DRC/LVS reports | Caravel-ready integration |
| [Sprint 12](sprints/sprint-12-tapeout-preparation.md) | Tapeout prep | signoff packet, manifests, release evidence | physical closure |
| [Sprint 13](sprints/sprint-13-post-silicon.md) | Post-silicon | bring-up logs, benchmarks, release notes, next-rev backlog | fabricated silicon |

## Cross-cutting workstreams

Every sprint should identify work in these lanes whenever relevant:

- Architecture and modeling: golden model, numerics, bandwidth, performance estimation, and architecture trade studies.
- RTL and microarchitecture: SystemVerilog blocks, interfaces, scheduler/control, and implementation details.
- Verification and formal: cocotb, self-checking benches, assertions, SymbiYosys properties, and regression evidence.
- Software and compiler: firmware, register programming model, command generation, graph lowering, and runtime APIs.
- Integration and physical design: FPGA wrapper work, Caravel harnessing, OpenLane, timing, power, DRC/LVS, and packaging.
- Documentation and reporting: ADRs, sprint updates, run reports, design reviews, and decision logs.

## Major decision gates

- Architecture gate after Sprint 1: freeze baseline tile shape, precision strategy, and ISA surface.
- Microarchitecture gate after Sprint 2: freeze interfaces, buffering strategy, and scheduler responsibilities.
- Block readiness gate after Sprints 3 to 5: each major RTL block must have unit tests and preliminary implementation evidence.
- Integration gate after Sprint 7: system-level control and dataflow must execute end-to-end directed workloads.
- Tapeout gate after Sprint 12: signoff evidence, packaging collateral, and regression archive must be complete.

## Success criteria

The program is successful when the following are all true:

- The accelerator executes attention-oriented tiled workloads with numerical agreement against the golden model.
- The software path can translate a supported model fragment into accelerator commands and drive execution.
- FPGA and simulation environments expose performance counters and reproducible benchmark evidence.
- Caravel integration is validated through control-path and firmware-driven tests.
- Physical-design artifacts reach a tapeout-ready state with timing, DRC, and LVS evidence recorded.
- Post-silicon validation reproduces at least one benchmarked attention inference demonstration.

## Main risks and mitigations

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Architecture chosen too early | Early RTL can lock in poor area/bandwidth trade-offs | Require golden-model and performance-model evidence before interface freeze |
| Caravel constraints discovered late | Harness, area, and bus limits can invalidate earlier assumptions | Treat Caravel as a parallel integration stream beginning no later than Sprint 10 |
| Verification debt | Late system bugs are expensive to isolate | Attach unit, formal, and report outputs to each block sprint |
| Physical closure misses target | SKY130 area/timing can force architectural compromises | Add synthesis and backend feedback to the design loop before tapeout sprints |
| Numerical mismatch | Softmax and quantization can drift from reference behavior | Build numeric study and bounded-error reporting into architecture and vector-unit work |

## Living links

- [Current State](current-state.md)
- [Architecture Docs](architecture/README.md)
- [Microarchitecture Docs](microarchitecture/README.md)
- [Sprint Plans](sprints/README.md)
- [Reports](reports/README.md)
- [Decisions](decisions/README.md)
