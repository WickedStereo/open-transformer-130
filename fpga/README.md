# FPGA synthesis flow

The existing iCE40 flow now targets the integrated `attn_core` top by default.

For a lightweight front-end smoke check, run:

```bash
make fpga-elab
```

This emits `build/fpga/attn_core_hierarchy.json` and prints a Yosys hierarchy/stat summary without committing to a specific board or place-and-route run.

Set the target part and package when running place-and-route:

```bash
make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48
```

Current state:

- Yosys front-end elaboration of `attn_core` succeeds in the repo toolchain.
- `make fpga-elab` is the preferred `08A` checkpoint because it is repeatable without board-specific collateral.
- The flow is still a smoke path only; there is no board-specific top wrapper, pin constraint file, or timing constraint set for a concrete FPGA board yet.
- The scratchpad still synthesizes from its behavioral wrapper model, so utilization/timing numbers are not representative of a macro-backed ASIC memory system.
