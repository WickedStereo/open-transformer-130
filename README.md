# open-transformer-130

Open-hardware transformer accelerator prototype with an integrated RTL baseline, cocotb verification, Yosys-compatible synthesis entry points, and OpenLane 2 collateral for the current `attn_core` top.

The devcontainer is currently optimized for simulation, cocotb, software tooling, and OpenLane. More ambitious FPGA toolchain pieces such as ECP5 support can be layered back in later once the core workflow is stable.

## Repository layout

- `.devcontainer/` development container definition
- `docker/` base development image
- `rtl/` SystemVerilog sources
- `sim/` C++ and cocotb simulation assets
- `software/` host-side runtime and firmware code
- `compiler/` compiler and lowering experiments
- `fpga/` FPGA bring-up collateral
- `openlane/` OpenLane 2 configuration
- `scripts/` helper automation
- `docs/` design notes and project documentation

## Project tracking

- `docs/progress/README.md` is the documentation hub for roadmap, decisions, reports, and sprint plans.
- `docs/progress/master-plan.md` captures the end-to-end accelerator program from scaffold to post-silicon validation.
- `docs/progress/current-state.md` records the current implemented baseline so future progress can be measured against it.
- `docs/progress/reports/2026-03-16-non-asic-closeout.md` summarizes the non-ASIC closeout (formal, FPGA bitstream, software/compiler baseline).

## Host PDK setup

On the Ubuntu host, install Volare and enable Sky130:

```bash
pip install volare
export PDK_ROOT=$HOME/pdk
volare enable --pdk sky130 --pdk-root $PDK_ROOT
```

The devcontainer bind-mounts `$HOME/pdk` from the host into `/pdk`, so using `export PDK_ROOT=$HOME/pdk` on the host matches the container setup directly. Inside the container, `PDK_ROOT` is set to `/pdk` automatically.

## Dev environment

1. Open Cursor and connect to this server with Remote SSH.
2. Open the folder `/home/anton/open-transformer-130`.
3. With the folder open, run `Dev Containers: Reopen in Container`.
4. Wait for the image build and the `postCreateCommand` pip installs to finish.
5. The devcontainer also bind-mounts the host Docker socket so `make gds` can launch OpenLane's official Dockerized flow from inside Cursor. Your host user must already be able to run `docker` without `sudo`.
6. The repo is mounted both at `/workspace` and at its original host path so OpenLane's nested Docker flow can hand the host daemon real mount paths instead of container-only paths.

## Main commands

```bash
make doctor
make lint
make formal
make sim
make test
make asic-prep
make fpga-elab
make fpga-demo-elab
make fpga-demo
make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48
make gds PDK_ROOT=$PDK_ROOT
```

`make doctor` is the Sprint 00 bootstrap check. It verifies the required lint/test toolchain, confirms the core Python packages are importable, and reports non-blocking gaps for optional later-sprint tooling such as OpenRAM, SymbiYosys, and Caravel-related infrastructure.

`make test` runs pytest across `sim/`, `software/`, and `compiler/`, including cocotb RTL tests and the runtime/lowering baseline.

`make formal` runs the bounded cvc4 proof suite for `mac_lane`, `isa_decoder`, `dma_engine`, and `tile_scheduler`.

`make asic-prep` is the lightweight pre-OpenLane `11A` smoke target. It lowers the integrated top through Yosys `prep`, emits `build/asic/attn_core_prep.json`, and prints a generic-cell inventory without requiring Docker or a full OpenLane run.

`make fpga-elab` is the lightweight `08A` front-end smoke target. It checks the `attn_core` hierarchy in Yosys, reports a design inventory, and writes `build/fpga/attn_core_hierarchy.json` without requiring a concrete FPGA board choice.

`make fpga-demo-elab` quickly elaborates the iCEBreaker demo wrapper. `make fpga-demo` runs full synthesis and place-and-route for the iCE40UP5K and produces `build/fpga/icebreaker_demo_top.bin`. See `fpga/README.md` for details.

`make fpga` is intentionally parameterized because the repo still does not lock to a single iCE40 board/package. The current flow now targets `attn_core` rather than the old stub top, but it remains a heavier board/package smoke path than `make fpga-elab`.

`make gds` uses `python3 -m openlane --dockerized`, which pulls and runs the official `ghcr.io/efabless/openlane2` container instead of relying on the in-container Yosys/OpenROAD stack. The first run can take a while because it needs to pull that image. Inside the devcontainer, the Makefile automatically falls back to `sudo` if the mounted Docker socket is only root-accessible.

## Notes

- `rtl/attn_core.sv` is the integrated prototype top and the default `make sim` / `make fpga` target.
- `fpga/fpga_attention_demo.sv` is a compact iCEBreaker demo wrapper that fits the iCE40UP5K; `fpga/icebreaker_demo_top.sv` and `fpga/icebreaker_demo.pcf` provide the board top and constraints.
- `software/runtime.py` and `compiler/lowering.py` provide the host-side runtime and attention descriptor lowering baseline.
- `rtl/attention_stub.sv` is retained only as a minimal placeholder module.
- `rtl/scratchpad_bank_1rw.sv` is the current SRAM swap point for future OpenRAM-style macro integration.
- `sim/reference_attention.py` provides the higher-level attention model, while `sim/rtl_scoreboard.py` mirrors the current fixed-point integrated datapath.
