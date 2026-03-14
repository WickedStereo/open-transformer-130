# open-transformer-130

Starter repository for an open-silicon + accelerator project with containerized development, RTL simulation, cocotb testing, placeholder FPGA synthesis, and OpenLane 2 integration points.

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

## Host PDK setup

On the Ubuntu host, install Volare and enable Sky130:

```bash
pip install volare
export PDK_ROOT=$HOME/pdk
volare enable --pdk sky130 --pdk-root $PDK_ROOT
```

The host `PDK_ROOT` directory is mounted into the devcontainer at `/pdk`, and the container sets `PDK_ROOT=/pdk` automatically.

## Dev environment

1. Open Cursor and connect to this server with Remote SSH.
2. Open the folder `/home/anton/open-transformer-130`.
3. With the folder open, run `Dev Containers: Reopen in Container`.
4. Wait for the image build and the `postCreateCommand` pip installs to finish.

## Main commands

```bash
make lint
make sim
make test
make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48
make gds PDK_ROOT=$PDK_ROOT
```

`make fpga` is intentionally parameterized because the scaffold does not lock the project to a specific iCE40 part or package yet.

## Notes

- `rtl/attention_stub.sv` is a placeholder module with the expected `clk` and `reset` signals.
- `sim/reference_attention.py` provides a NumPy golden model for future attention datapath comparisons.
- `sim/test_attention.py` demonstrates the cocotb reset/clock pattern and shows where to compare DUT outputs to the Python reference.
