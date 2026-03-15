"""Unit tests for perf_counters."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.soft_reset.value = 0
    dut.busy_inc.value = 0
    dut.stall_inc.value = 0
    dut.dma_bytes_inc.value = 0
    dut.dma_bytes_valid.value = 0
    dut.tile_inc.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_increment_paths(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.busy_inc.value = 1
    dut.stall_inc.value = 1
    dut.dma_bytes_inc.value = 24
    dut.dma_bytes_valid.value = 1
    dut.tile_inc.value = 1
    await RisingEdge(dut.clk)

    dut.busy_inc.value = 0
    dut.stall_inc.value = 0
    dut.dma_bytes_valid.value = 0
    dut.tile_inc.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.busy_cycles.value) == 1
    assert int(dut.stall_cycles.value) == 1
    assert int(dut.dma_bytes.value) == 24
    assert int(dut.tile_count.value) == 1


@cocotb.test()
async def test_soft_reset_clears_counters(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.busy_inc.value = 1
    dut.stall_inc.value = 1
    dut.dma_bytes_inc.value = 16
    dut.dma_bytes_valid.value = 1
    dut.tile_inc.value = 1
    await RisingEdge(dut.clk)

    dut.busy_inc.value = 0
    dut.stall_inc.value = 0
    dut.dma_bytes_valid.value = 0
    dut.tile_inc.value = 0
    dut.soft_reset.value = 1
    await RisingEdge(dut.clk)
    dut.soft_reset.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.busy_cycles.value) == 0
    assert int(dut.stall_cycles.value) == 0
    assert int(dut.dma_bytes.value) == 0
    assert int(dut.tile_count.value) == 0


@cocotb.test()
async def test_saturates_without_wrapping(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.dma_bytes_inc.value = 0xFFFFFFFE
    dut.dma_bytes_valid.value = 1
    await RisingEdge(dut.clk)
    dut.dma_bytes_inc.value = 8
    await RisingEdge(dut.clk)
    dut.dma_bytes_valid.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.dma_bytes.value) == 0xFFFFFFFF


def test_perf_counters_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "perf_counters.sv"],
        hdl_toplevel="perf_counters",
        build_dir=str(repo_root / "build" / "test_perf_counters"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="perf_counters",
        test_module="sim.test_perf_counters",
    )
