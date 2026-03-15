"""Unit tests for vector_unit."""

import os
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from sim.rtl_scoreboard import softmax_fixed

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


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.cmd_valid.value = 0
    dut.cmd_src_slot.value = 0
    dut.cmd_dst_slot.value = 0
    dut.cmd_rows.value = 0
    dut.cmd_cols.value = 0
    dut.cmd_approx.value = 1
    dut.scratch_grant.value = 0
    dut.scratch_rdata.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def serve_scratch(dut, memory, timeout=1200):
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


async def issue_softmax(dut, src_slot, dst_slot, rows, cols):
    dut.cmd_valid.value = 1
    dut.cmd_src_slot.value = src_slot
    dut.cmd_dst_slot.value = dst_slot
    dut.cmd_rows.value = rows
    dut.cmd_cols.value = cols
    dut.cmd_approx.value = 1
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0


def slot_addr(slot_id: int, offset: int) -> int:
    return (slot_id << 12) + offset


@cocotb.test()
async def test_single_row_softmax(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    scores = np.array([[3, 1, -2, 3]], dtype=np.int8)
    expected = softmax_fixed(scores)
    scratch_mem = {}
    for idx, value in enumerate(scores[0]):
        scratch_mem[slot_addr(0, idx)] = int(value) & 0xFF

    cocotb.start_soon(serve_scratch(dut, scratch_mem))
    await issue_softmax(dut, src_slot=0, dst_slot=1, rows=1, cols=4)

    for _ in range(400):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    observed = np.array(
        [[scratch_mem[slot_addr(1, idx)] for idx in range(4)]],
        dtype=np.uint8,
    )
    np.testing.assert_array_equal(observed, expected)


@cocotb.test()
async def test_two_row_softmax_tile(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    scores = np.array(
        [
            [2, 0, -1, 2],
            [-3, -3, 4, 0],
        ],
        dtype=np.int8,
    )
    expected = softmax_fixed(scores)
    scratch_mem = {}
    for row in range(scores.shape[0]):
        for col in range(scores.shape[1]):
            scratch_mem[slot_addr(0, row * scores.shape[1] + col)] = int(scores[row, col]) & 0xFF

    cocotb.start_soon(serve_scratch(dut, scratch_mem))
    await issue_softmax(dut, src_slot=0, dst_slot=1, rows=2, cols=4)

    for _ in range(800):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    observed = np.zeros_like(expected)
    for row in range(scores.shape[0]):
        for col in range(scores.shape[1]):
            observed[row, col] = scratch_mem[slot_addr(1, row * scores.shape[1] + col)]

    np.testing.assert_array_equal(observed, expected)


def test_vector_unit_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "vector_unit.sv"],
        hdl_toplevel="vector_unit",
        build_dir=str(repo_root / "build" / "test_vector_unit"),
        always=True,
        build_args=["--sv", "-Wno-WIDTHTRUNC"],
    )

    runner.test(
        hdl_toplevel="vector_unit",
        test_module="sim.test_vector_unit",
    )
