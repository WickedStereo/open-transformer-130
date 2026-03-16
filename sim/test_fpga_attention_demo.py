"""Simulation smoke test for the FPGA-friendly attention demo wrapper."""

from __future__ import annotations

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


@cocotb.test()
async def test_fpga_attention_demo_runs_directed_workload(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.btn_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)

    dut.btn_n.value = 1

    for _ in range(12000):
        await RisingEdge(dut.clk)
        if int(dut.demo_done.value):
            break

    assert int(dut.demo_done.value) == 1, "demo wrapper never completed"
    assert int(dut.demo_pass.value) == 1, "demo wrapper did not produce expected output"
    assert int(dut.demo_fault.value) == 0, "demo wrapper should not fault"
    assert int(dut.tail_snapshot.value) == 7, "all queued commands should retire"
    assert int(dut.output_word.value) == 0x2218190F, "unexpected stored output tile"


def test_fpga_attention_demo_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    rtl_dir = repo_root / "rtl"
    sources = [
        rtl_dir / "mmio_regs.sv",
        rtl_dir / "queue_ctrl.sv",
        rtl_dir / "isa_decoder.sv",
        rtl_dir / "tile_scheduler.sv",
        rtl_dir / "dma_engine.sv",
        rtl_dir / "bank_arbiter.sv",
        rtl_dir / "mac_lane.sv",
        rtl_dir / "mac_array.sv",
        rtl_dir / "compute_engine.sv",
        rtl_dir / "scratchpad_bank_1rw.sv",
        rtl_dir / "scratchpad.sv",
        rtl_dir / "vector_unit.sv",
        rtl_dir / "perf_counters.sv",
        rtl_dir / "attn_core.sv",
        repo_root / "fpga" / "fpga_attention_demo.sv",
    ]

    runner.build(
        sources=sources,
        hdl_toplevel="fpga_attention_demo",
        build_dir=str(repo_root / "build" / "test_fpga_attention_demo"),
        always=True,
        build_args=["--sv", "-Wno-MULTITOP", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="fpga_attention_demo",
        test_module="sim.test_fpga_attention_demo",
    )
