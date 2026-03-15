"""Unit tests for tile_scheduler."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner

ACT_NOP = 0
ACT_DMA = 1
ACT_COMPUTE = 2

SLOT_FREE = 0b00
SLOT_LOADING = 0b01
SLOT_RESIDENT = 0b10


def slot_state(slot_state_out: int, slot_id: int) -> int:
    return (slot_state_out >> (slot_id * 2)) & 0b11


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.action_valid.value = 0
    dut.action_type.value = 0
    dut.action_load.value = 0
    dut.action_src_slot.value = 0
    dut.action_dst_slot.value = 0
    dut.action_dim_m.value = 0
    dut.action_dim_n.value = 0
    dut.action_dim_k.value = 0
    dut.action_flags.value = 0
    dut.action_host_addr.value = 0
    dut.dma_cmd_ready.value = 0
    dut.dma_done.value = 0
    dut.dma_error.value = 0
    dut.compute_cmd_ready.value = 0
    dut.compute_done.value = 0
    dut.vector_cmd_ready.value = 0
    dut.vector_done.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.enable.value = 1
    await RisingEdge(dut.clk)


async def issue_action(
    dut,
    *,
    action_type,
    action_load=0,
    src_slot=0,
    dst_slot=0,
    m=4,
    n=4,
    k=4,
    flags=0,
):
    while int(dut.action_ready.value) == 0:
        await RisingEdge(dut.clk)

    dut.action_type.value = action_type
    dut.action_load.value = action_load
    dut.action_src_slot.value = src_slot
    dut.action_dst_slot.value = dst_slot
    dut.action_dim_m.value = m
    dut.action_dim_n.value = n
    dut.action_dim_k.value = k
    dut.action_flags.value = flags
    dut.action_valid.value = 1
    await RisingEdge(dut.clk)
    dut.action_valid.value = 0


async def complete_dma_load(dut, slot_id: int):
    dut.dma_cmd_ready.value = 1
    await issue_action(dut, action_type=ACT_DMA, action_load=1, dst_slot=slot_id)

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.dma_cmd_valid.value):
            break

    assert int(dut.dma_cmd_valid.value) == 1
    await RisingEdge(dut.clk)
    assert slot_state(int(dut.slot_state_out.value), slot_id) == SLOT_LOADING

    dut.dma_done.value = 1
    await RisingEdge(dut.clk)
    dut.dma_done.value = 0
    await RisingEdge(dut.clk)

    assert slot_state(int(dut.slot_state_out.value), slot_id) == SLOT_RESIDENT
    dut.dma_cmd_ready.value = 0


@cocotb.test()
async def test_dma_load_transitions_slot_to_resident(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await complete_dma_load(dut, slot_id=2)


@cocotb.test()
async def test_compute_issues_only_after_slots_are_resident(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await complete_dma_load(dut, slot_id=0)
    await complete_dma_load(dut, slot_id=1)

    dut.compute_cmd_ready.value = 1
    await issue_action(
        dut,
        action_type=ACT_COMPUTE,
        src_slot=0,
        dst_slot=1,
        m=2,
        n=2,
        k=2,
    )

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.compute_cmd_valid.value):
            break

    assert int(dut.compute_cmd_valid.value) == 1
    dut.compute_done.value = 1
    await RisingEdge(dut.clk)
    dut.compute_done.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.busy.value) == 0


def test_tile_scheduler_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "tile_scheduler.sv"],
        hdl_toplevel="tile_scheduler",
        build_dir=str(repo_root / "build" / "test_tile_scheduler"),
        always=True,
        build_args=["--sv", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="tile_scheduler",
        test_module="sim.test_tile_scheduler",
    )
