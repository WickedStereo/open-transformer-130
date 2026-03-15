# Sprint 02 - Microarchitecture Design

Status: done

## Objective

Translate the frozen architecture into block-level responsibilities, interfaces, buffering rules, and verification hooks suitable for RTL implementation.

## Deliverables

- microarchitecture specs for compute, memory, control, vector/softmax, and debug blocks
- interface definitions between scheduler, DMA, scratchpad, compute, and status logic
- verification matrix for unit, integration, and formal targets
- physical-awareness notes for area, clocking, and floorplan pressure points

## Dependencies

- Sprint 01 architecture decisions
- baseline tensor ISA and memory assumptions

## Parallelization Note

Compute, memory, and control subteams can work in parallel once the Sprint 1 architecture gate is closed.

## Parallel Workstreams

### Compute-datapath lane

- define `mac_lane` and `mac_array` interfaces, pipeline cuts, and accumulation behavior
- record saturation, rounding, and partial-sum lifetime rules
- identify critical timing paths that should influence RTL partitioning

### Memory-subsystem lane

- define scratchpad banking and addressing scheme
- assign DMA responsibilities and completion semantics
- define how the scheduler tracks tile residency and hazards

### Control-plane lane

- map ISA fields into decoder outputs and scheduler actions
- define command-queue semantics and status register behavior
- freeze counter visibility and debug-register requirements

### Verification-planning lane

- assign tests and properties to each block before RTL starts
- define scoreboards, assertions, and expected coverage points
- capture invalid-state and deadlock cases to target formally later

### Physical-awareness lane

- estimate which blocks will dominate area and routing
- record clocking and reset assumptions
- note implementation choices that should remain flexible until synthesis feedback arrives

## Exit Criteria

- interfaces are stable enough to let block RTL proceed independently
- no major ownership ambiguity remains between compute, memory, and control blocks
- verification expectations are attached to each upcoming RTL sprint

## Evidence Captured

- [Compute Datapath Spec](../microarchitecture/compute-datapath.md)
- [Memory Subsystem Spec](../microarchitecture/memory-subsystem.md)
- [Control Plane Spec](../microarchitecture/control-plane.md)
- [Vector/Softmax Spec](../microarchitecture/vector-softmax.md)
- [Debug and Observability Spec](../microarchitecture/debug-and-observability.md)
- [Block Interface Definitions](../microarchitecture/interfaces.md)
- [Physical Awareness Notes](../microarchitecture/physical-awareness.md)
- [Verification Matrix](../reports/2026-03-15-verification-matrix.md)

## Open Risks And Decisions

- unstable interfaces will create churn across multiple RTL blocks
- physical constraints may force changes in the chosen array width or scratchpad topology
