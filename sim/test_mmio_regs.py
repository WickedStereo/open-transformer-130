"""Unit tests for mmio_regs: MMIO register read/write behavior."""

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
    dut.mmio_valid.value = 0
    dut.mmio_wen.value = 0
    dut.mmio_addr.value = 0
    dut.mmio_wdata.value = 0
    dut.cmd_tail.value = 0
    dut.status_busy.value = 0
    dut.status_fault.value = 0
    dut.status_dma_active.value = 0
    dut.status_compute_active.value = 0
    dut.status_queue_depth.value = 0
    dut.fault_info_desc.value = 0
    dut.fault_info_opcode.value = 0
    dut.fault_info_cause.value = 0
    dut.perf_busy_cycles.value = 0
    dut.perf_stall_cycles.value = 0
    dut.perf_dma_bytes.value = 0
    dut.perf_tile_count.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def write_reg(dut, offset, value):
    dut.mmio_valid.value = 1
    dut.mmio_wen.value = 1
    dut.mmio_addr.value = offset
    dut.mmio_wdata.value = value
    await RisingEdge(dut.clk)
    dut.mmio_valid.value = 0
    dut.mmio_wen.value = 0


async def read_reg(dut, offset):
    dut.mmio_valid.value = 1
    dut.mmio_wen.value = 0
    dut.mmio_addr.value = offset
    await RisingEdge(dut.clk)
    dut.mmio_valid.value = 0
    return int(dut.mmio_rdata.value)


@cocotb.test()
async def test_default_tile_dimensions(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    assert int(dut.tile_default_m.value) == 64
    assert int(dut.tile_default_n.value) == 64
    assert int(dut.tile_default_k.value) == 64


@cocotb.test()
async def test_write_read_ctrl(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_reg(dut, 0x00, 0x01)  # enable bit
    val = await read_reg(dut, 0x00)
    assert val & 1 == 1
    assert int(dut.ctrl_enable.value) == 1


@cocotb.test()
async def test_write_read_queue_base(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_reg(dut, 0x08, 0xDEAD0000)
    val = await read_reg(dut, 0x08)
    assert val == 0xDEAD0000, f"got {val:#x}"


@cocotb.test()
async def test_write_read_head(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_reg(dut, 0x10, 42)
    val = await read_reg(dut, 0x10)
    assert val == 42


@cocotb.test()
async def test_tail_is_readonly(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.cmd_tail.value = 7
    await write_reg(dut, 0x14, 99)  # attempt write (should be ignored)
    val = await read_reg(dut, 0x14)
    assert val == 7, f"tail should be read-only, got {val}"


@cocotb.test()
async def test_status_register(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.status_busy.value = 1
    dut.status_fault.value = 1
    dut.status_dma_active.value = 1
    dut.status_queue_depth.value = 5
    await RisingEdge(dut.clk)

    val = await read_reg(dut, 0x04)
    assert val & 0x01 == 1, "busy bit"
    assert (val >> 1) & 1 == 1, "fault bit"
    assert (val >> 2) & 1 == 1, "dma_active bit"
    assert (val >> 4) & 0xF == 5, "queue_depth"


@cocotb.test()
async def test_perf_counters_readable(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.perf_busy_cycles.value = 1000
    dut.perf_stall_cycles.value = 200
    dut.perf_dma_bytes.value = 4096
    dut.perf_tile_count.value = 10
    await RisingEdge(dut.clk)

    assert await read_reg(dut, 0x28) == 1000
    assert await read_reg(dut, 0x2C) == 200
    assert await read_reg(dut, 0x30) == 4096
    assert await read_reg(dut, 0x34) == 10


@cocotb.test()
async def test_soft_reset_clears_registers(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_reg(dut, 0x08, 0x12345678)
    await write_reg(dut, 0x1C, 32)  # default_m

    # Issue soft reset
    await write_reg(dut, 0x00, 0x02)
    await RisingEdge(dut.clk)

    val = await read_reg(dut, 0x08)
    assert val == 0, f"queue_base should be cleared, got {val:#x}"
    assert int(dut.tile_default_m.value) == 64, "defaults should be restored"


@cocotb.test()
async def test_dma_host_addr(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_reg(dut, 0x38, 0xCAFE0000)
    val = await read_reg(dut, 0x38)
    assert val == 0xCAFE0000


def test_mmio_regs_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "mmio_regs.sv"],
        hdl_toplevel="mmio_regs",
        build_dir=str(repo_root / "build" / "test_mmio_regs"),
        always=True,
        build_args=["--sv", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="mmio_regs",
        test_module="sim.test_mmio_regs",
    )
