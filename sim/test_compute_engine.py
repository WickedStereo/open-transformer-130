"""Unit tests for compute_engine."""

import os
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from sim.rtl_scoreboard import matmul_tile

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner

ADDR_W = 14
DATA_W = 8


def unpack_addrs(packed: int, bank: int) -> int:
    return (packed >> (bank * ADDR_W)) & ((1 << ADDR_W) - 1)


def unpack_data(packed: int, bank: int) -> int:
    return (packed >> (bank * DATA_W)) & 0xFF


def slot_addr(slot_id: int, offset: int) -> int:
    return (slot_id << 12) + offset


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.cmd_valid.value = 0
    dut.cmd_src_slot.value = 0
    dut.cmd_src2_slot.value = 0
    dut.cmd_dst_slot.value = 0
    dut.cmd_dim_m.value = 0
    dut.cmd_dim_n.value = 0
    dut.cmd_dim_k.value = 0
    dut.cmd_accum.value = 0
    dut.cmd_saturate.value = 1
    dut.cmd_shift.value = 0
    dut.scratch_grant.value = 0
    dut.scratch_rdata.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def serve_scratch(dut, memory, timeout=2000):
    pending_bank = None
    pending_addr = None
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        dut.scratch_grant.value = 0
        dut.scratch_rdata.value = 0

        if pending_bank is not None:
            dut.scratch_rdata.value = memory.get(pending_addr, 0) << (pending_bank * DATA_W)
            pending_bank = None
            pending_addr = None

        req = int(dut.scratch_req.value)
        if req == 0:
            continue

        bank = (req & -req).bit_length() - 1
        addr = unpack_addrs(int(dut.scratch_addr.value), bank)
        abs_addr = (bank << ADDR_W) | addr
        dut.scratch_grant.value = 1 << bank

        if (int(dut.scratch_wen.value) >> bank) & 1:
            memory[abs_addr] = unpack_data(int(dut.scratch_wdata.value), bank)
        else:
            pending_bank = bank
            pending_addr = abs_addr


@cocotb.test()
async def test_matmul_writes_expected_tile(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    lhs = np.array([[2, 1], [1, 3]], dtype=np.int8)
    rhs = np.array([[1, -1], [2, 1]], dtype=np.int8)
    expected = matmul_tile(lhs, rhs)

    scratch_mem = {}
    for idx, value in enumerate(lhs.flatten()):
        scratch_mem[slot_addr(0, idx)] = int(value) & 0xFF
    for idx, value in enumerate(rhs.flatten()):
        scratch_mem[slot_addr(1, idx)] = int(value) & 0xFF

    cocotb.start_soon(serve_scratch(dut, scratch_mem))

    dut.cmd_valid.value = 1
    dut.cmd_src_slot.value = 0
    dut.cmd_src2_slot.value = 1
    dut.cmd_dst_slot.value = 2
    dut.cmd_dim_m.value = 2
    dut.cmd_dim_n.value = 2
    dut.cmd_dim_k.value = 2
    dut.cmd_saturate.value = 1
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0

    for _ in range(1200):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    observed = np.array(
        [
            [scratch_mem[slot_addr(2, 0)], scratch_mem[slot_addr(2, 1)]],
            [scratch_mem[slot_addr(2, 2)], scratch_mem[slot_addr(2, 3)]],
        ],
        dtype=np.uint8,
    ).view(np.int8)
    np.testing.assert_array_equal(observed, expected)


@cocotb.test()
async def test_in_place_rhs_overwrite_uses_prefetched_rhs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    lhs = np.array([[2, 1], [1, 3]], dtype=np.int8)
    rhs = np.array([[1, -1], [2, 1]], dtype=np.int8)
    expected = matmul_tile(lhs, rhs)

    scratch_mem = {}
    for idx, value in enumerate(lhs.flatten()):
        scratch_mem[slot_addr(0, idx)] = int(value) & 0xFF
    for idx, value in enumerate(rhs.flatten()):
        scratch_mem[slot_addr(1, idx)] = int(value) & 0xFF

    cocotb.start_soon(serve_scratch(dut, scratch_mem))

    dut.cmd_valid.value = 1
    dut.cmd_src_slot.value = 0
    dut.cmd_src2_slot.value = 1
    dut.cmd_dst_slot.value = 1
    dut.cmd_dim_m.value = 2
    dut.cmd_dim_n.value = 2
    dut.cmd_dim_k.value = 2
    dut.cmd_saturate.value = 1
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0

    for _ in range(1200):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    observed = np.array(
        [
            [scratch_mem[slot_addr(1, 0)], scratch_mem[slot_addr(1, 1)]],
            [scratch_mem[slot_addr(1, 2)], scratch_mem[slot_addr(1, 3)]],
        ],
        dtype=np.uint8,
    ).view(np.int8)
    np.testing.assert_array_equal(observed, expected)


def test_compute_engine_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[
            repo_root / "rtl" / "mac_lane.sv",
            repo_root / "rtl" / "mac_array.sv",
            repo_root / "rtl" / "compute_engine.sv",
        ],
        hdl_toplevel="compute_engine",
        build_dir=str(repo_root / "build" / "test_compute_engine"),
        always=True,
        build_args=["--sv", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="compute_engine",
        test_module="sim.test_compute_engine",
    )
