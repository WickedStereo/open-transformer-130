# FPGA synthesis flow

The repo now has two FPGA-oriented paths:

1. The generic integrated-core smoke flow for `attn_core`
2. An iCEBreaker-specific demo wrapper that boots a directed attention workload internally

## 08A smoke flow

For a lightweight front-end checkpoint on the raw integrated top, run:

```bash
make fpga-elab
```

This emits `build/fpga/attn_core_hierarchy.json` and keeps `08A` fast and reproducible.

If you want the heavier generic iCE40 place-and-route experiment, keep using:

```bash
make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48
```

## 08B board wrapper

The iCEBreaker demo collateral lives in:

- `fpga/fpga_attention_demo.sv`: compact directed attention wrapper built from `compute_engine` and the scratchpad path
- `fpga/icebreaker_demo_top.sv`: iCEBreaker board wrapper
- `fpga/icebreaker_demo.pcf`: clock, button, and LED constraints

The demo workload is the current supported single-tile attention fragment:

1. Load `Q`
2. Load `K^T`
3. Compute score tile
4. Run softmax
5. Load `V`
6. Compute attention output
7. Store the output tile back to host memory

For a fast wrapper-elaboration check, run:

```bash
make fpga-demo-elab
```

The demo wrapper is intentionally smaller than the full integrated `attn_core` path. It reuses the scratchpad-backed compute datapath, preloads the fixed demo tiles directly on-chip, and writes the precomputed softmax weights for this directed workload so the UP5K board build stays tractable.

For the board-specific bitstream build, run:

```bash
make fpga-demo
```

On the current compact wrapper, the routed iCEBreaker build uses `2648 / 5280` logic cells (50%), `4 / 30` block RAMs, and reports `20.10 MHz` routed Fmax against the `12 MHz` target. `icepack` emits the loadable bitstream at `build/fpga/icebreaker_demo_top.bin`.

This is intentionally the heavier `08B` evidence path; use `make fpga-demo-elab` as the quick iteration loop and reserve `make fpga-demo` for full board-build validation.

`fpga_attention_demo` is also covered by the cocotb regression through `sim/test_fpga_attention_demo.py`, which checks that the wrapper completes and that the stored output bytes match the expected fixed-point attention result.

## Demo observability

On the iCEBreaker snap-off LED bank:

- `leds[0]`: heartbeat
- `leds[1]`: demo started
- `leds[2]`: demo finished
- `leds[3]`: demo pass
- `leds[4]`: demo fault

## Limitations

- The scratchpad is still synthesized from the behavioral bank wrapper, so FPGA area and timing remain pessimistic relative to a BRAM-specialized implementation.
- The wrapper uses precomputed softmax weights for this fixed directed workload so the UP5K demo stays tractable; it is a compact board bring-up path, not a general FPGA deployment of the full `attn_core` stack.
- The demo wrapper uses an internal host-memory model for bring-up convenience; it is a board-level validation step, not a replacement for the host/runtime flow in `software/`.
