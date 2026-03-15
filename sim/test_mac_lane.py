"""Unit tests for mac_lane: 3-stage pipelined multiply-accumulate."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


PIPE_LATENCY = 2  # cycles after last op_valid before accumulator settles


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.op_valid.value = 0
    dut.op_a.value = 0
    dut.op_b.value = 0
    dut.accum_clear.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def feed(dut, a, b, clear=False):
    dut.op_valid.value = 1
    dut.op_a.value = a & 0xFF
    dut.op_b.value = b & 0xFF
    dut.accum_clear.value = int(clear)
    await RisingEdge(dut.clk)
    dut.op_valid.value = 0
    dut.accum_clear.value = 0


async def drain(dut, extra=1):
    for _ in range(PIPE_LATENCY + extra):
        await RisingEdge(dut.clk)


def accum(dut):
    v = dut.accum_out.value
    return v.to_signed() if hasattr(v, "to_signed") else v.signed_integer


# ── Tests ──


@cocotb.test()
async def test_reset_clears_accumulator(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    assert accum(dut) == 0
    assert int(dut.lane_busy.value) == 0


@cocotb.test()
async def test_single_positive_mac(dut):
    """3 × 4 = 12."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, 3, 4, clear=True)
    await drain(dut)
    assert accum(dut) == 12, f"got {accum(dut)}"


@cocotb.test()
async def test_single_negative_mac(dut):
    """-3 × 4 = -12."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, -3 & 0xFF, 4, clear=True)
    await drain(dut)
    assert accum(dut) == -12, f"got {accum(dut)}"


@cocotb.test()
async def test_accumulation(dut):
    """3×4 + 5×6 = 42."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, 3, 4, clear=True)
    await feed(dut, 5, 6)
    await drain(dut)
    assert accum(dut) == 42, f"got {accum(dut)}"


@cocotb.test()
async def test_accum_clear_resets(dut):
    """Accumulate 3×4=12, then clear and accumulate 2×5=10."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, 3, 4, clear=True)
    await drain(dut)
    assert accum(dut) == 12

    await feed(dut, 2, 5, clear=True)
    await drain(dut)
    assert accum(dut) == 10, f"got {accum(dut)}"


@cocotb.test()
async def test_boundary_positive(dut):
    """127 × 127 = 16129."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, 127, 127, clear=True)
    await drain(dut)
    assert accum(dut) == 16129, f"got {accum(dut)}"


@cocotb.test()
async def test_boundary_negative_times_negative(dut):
    """-128 × -128 = 16384."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, (-128) & 0xFF, (-128) & 0xFF, clear=True)
    await drain(dut)
    assert accum(dut) == 16384, f"got {accum(dut)}"


@cocotb.test()
async def test_boundary_cross_sign(dut):
    """-128 × 127 = -16256."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, (-128) & 0xFF, 127, clear=True)
    await drain(dut)
    assert accum(dut) == -16256, f"got {accum(dut)}"


@cocotb.test()
async def test_zero_operands(dut):
    """0 × anything = 0."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await feed(dut, 0, 127, clear=True)
    await drain(dut)
    assert accum(dut) == 0

    await feed(dut, 127, 0, clear=True)
    await drain(dut)
    assert accum(dut) == 0


@cocotb.test()
async def test_multi_step_accumulation(dut):
    """Accumulate 4 products: 1×1 + 2×2 + 3×3 + 4×4 = 30."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    pairs = [(1, 1), (2, 2), (3, 3), (4, 4)]
    for i, (a, b) in enumerate(pairs):
        await feed(dut, a, b, clear=(i == 0))
    await drain(dut)
    assert accum(dut) == 30, f"got {accum(dut)}"


@cocotb.test()
async def test_lane_busy_flag(dut):
    """lane_busy should be high while pipeline has in-flight data."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    assert int(dut.lane_busy.value) == 0

    await feed(dut, 1, 1, clear=True)
    # After feed(), s1 captured the data. Advance one cycle so s2 is active.
    await RisingEdge(dut.clk)
    assert int(dut.lane_busy.value) == 1, "pipeline should be busy during multiply stage"

    await drain(dut, extra=2)
    assert int(dut.lane_busy.value) == 0, "pipeline should be idle after drain"


# ── pytest entry point ──


def test_mac_lane_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "mac_lane.sv"],
        hdl_toplevel="mac_lane",
        build_dir=str(repo_root / "build" / "test_mac_lane"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="mac_lane",
        test_module="sim.test_mac_lane",
    )
