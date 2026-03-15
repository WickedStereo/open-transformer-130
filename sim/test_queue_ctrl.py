"""Unit tests for queue_ctrl."""

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
    dut.queue_base.value = 0
    dut.queue_size_log2.value = 0
    dut.head.value = 0
    dut.fault_halt.value = 0
    dut.enable.value = 0
    dut.desc_consumed.value = 0
    dut.bus_rdata.value = 0
    dut.bus_ack.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def serve_queue_bus(dut, descriptors, timeout=200):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        dut.bus_ack.value = 0
        if int(dut.bus_req.value):
            addr = int(dut.bus_addr.value)
            idx = (addr >> 3) & 0xFF
            dut.bus_rdata.value = descriptors[idx % len(descriptors)]
            dut.bus_ack.value = 1


@cocotb.test()
async def test_single_descriptor_fetch(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    descriptors = [0x1122334455667788]
    cocotb.start_soon(serve_queue_bus(dut, descriptors))

    dut.queue_base.value = 0
    dut.queue_size_log2.value = 2  # depth 4
    dut.head.value = 1
    dut.enable.value = 1

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.desc_valid.value):
            break

    assert int(dut.desc_valid.value) == 1
    assert int(dut.desc_data.value) == descriptors[0]

    dut.desc_consumed.value = 1
    await RisingEdge(dut.clk)
    dut.desc_consumed.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.tail.value) == 1


@cocotb.test()
async def test_fault_halt_blocks_fetch(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.queue_base.value = 0
    dut.queue_size_log2.value = 2
    dut.head.value = 1
    dut.enable.value = 1
    dut.fault_halt.value = 1

    for _ in range(10):
        await RisingEdge(dut.clk)

    assert int(dut.bus_req.value) == 0
    assert int(dut.desc_valid.value) == 0
    assert int(dut.tail.value) == 0


@cocotb.test()
async def test_wraparound_uses_ring_mask(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    descriptors = [0xAA, 0xBB]
    cocotb.start_soon(serve_queue_bus(dut, descriptors, timeout=400))

    dut.queue_base.value = 0
    dut.queue_size_log2.value = 1  # depth 2
    dut.head.value = 3
    dut.enable.value = 1

    seen = []
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.desc_valid.value):
            seen.append(int(dut.desc_data.value))
            dut.desc_consumed.value = 1
            await RisingEdge(dut.clk)
            dut.desc_consumed.value = 0
            if len(seen) == 3:
                break

    await RisingEdge(dut.clk)
    assert seen == [0xAA, 0xBB, 0xAA]
    assert int(dut.tail.value) == 1


def test_queue_ctrl_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "queue_ctrl.sv"],
        hdl_toplevel="queue_ctrl",
        build_dir=str(repo_root / "build" / "test_queue_ctrl"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="queue_ctrl",
        test_module="sim.test_queue_ctrl",
    )
