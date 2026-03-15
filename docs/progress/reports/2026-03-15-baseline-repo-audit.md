# Baseline Repo Audit

Date: 2026-03-15
Report type: repository baseline

## Objective

Capture the repository starting point before architecture freeze, RTL expansion, or Caravel integration work begins.

## Scope reviewed

- repository layout and root documentation
- devcontainer and base Docker image
- Makefile entrypoints
- CI workflow
- current RTL, simulation, FPGA, and OpenLane assets

## Key findings

| Topic | Finding | Evidence |
| --- | --- | --- |
| Repo maturity | Starter scaffold, not a partial accelerator implementation | [README](../../../README.md) |
| RTL state | Only a simple pass-through placeholder exists | [rtl/attention_stub.sv](../../../rtl/attention_stub.sv) |
| Golden model | Minimal NumPy attention implementation exists and is suitable as a seed model | [sim/reference_attention.py](../../../sim/reference_attention.py) |
| Verification | A cocotb test skeleton and a Verilator path exist, but no block-level suites or scoreboards | [sim/test_attention.py](../../../sim/test_attention.py), [sim/main.cpp](../../../sim/main.cpp) |
| Dev environment | Container setup is already useful for early-stage RTL/modeling work | [.devcontainer/devcontainer.json](../../../.devcontainer/devcontainer.json), [docker/Dockerfile](../../../docker/Dockerfile) |
| CI | Only lint and cocotb test are automated today | [.github/workflows/test.yml](../../../.github/workflows/test.yml) |
| FPGA | The iCE40 path is placeholder-level and lacks board collateral | [fpga/README.md](../../../fpga/README.md) |
| ASIC flow | OpenLane smoke config exists for the stub design only | [openlane/config.json](../../../openlane/config.json) |
| Caravel | No integration collateral present yet | repository search result |

## Program-level interpretation

- The repository is ready for disciplined planning and staged implementation.
- Architecture exploration and documentation are the highest-leverage next steps.
- Caravel, formal, and backend flows must be introduced as new project capabilities rather than treated as refinement of existing subsystems.

## Recommended immediate actions

- Establish a durable documentation and progress-tracking structure under `docs/`.
- Freeze the first architecture baseline and tensor ISA assumptions before writing substantial RTL.
- Expand the golden model and performance model before microarchitecture is locked.
- Treat verification, FPGA, and physical-design evidence as report-producing workstreams from the outset.

## Linked snapshot

See [Current State](../current-state.md) for the living baseline document.
