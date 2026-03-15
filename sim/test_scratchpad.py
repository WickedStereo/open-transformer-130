"""Unit tests for scratchpad: 8-bank behavioral SRAM."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner

ADDR_W = 14
DATA_W = 8
NUM_BANKS = 8


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.bank_en.value = 0
    dut.bank_wen.value = 0
    dut.bank_addr.value = 0
    dut.bank_wdata.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def set_bank_en(dut, bank):
    dut.bank_en.value = 1 << bank


def set_bank_write(dut, bank, addr, data):
    dut.bank_en.value = 1 << bank
    dut.bank_wen.value = 1 << bank
    mask_a = ((1 << ADDR_W) - 1) << (bank * ADDR_W)
    old_addr = int(dut.bank_addr.value) & ~mask_a
    dut.bank_addr.value = old_addr | (addr << (bank * ADDR_W))
    mask_d = ((1 << DATA_W) - 1) << (bank * DATA_W)
    old_wd = int(dut.bank_wdata.value) & ~mask_d
    dut.bank_wdata.value = old_wd | (data << (bank * DATA_W))


def set_bank_read(dut, bank, addr):
    dut.bank_en.value = 1 << bank
    dut.bank_wen.value = 0
    mask_a = ((1 << ADDR_W) - 1) << (bank * ADDR_W)
    old_addr = int(dut.bank_addr.value) & ~mask_a
    dut.bank_addr.value = old_addr | (addr << (bank * ADDR_W))


def get_bank_rdata(dut, bank):
    raw = int(dut.bank_rdata.value)
    return (raw >> (bank * DATA_W)) & ((1 << DATA_W) - 1)


async def write_byte(dut, bank, addr, data):
    set_bank_write(dut, bank, addr, data)
    await RisingEdge(dut.clk)
    dut.bank_en.value = 0
    dut.bank_wen.value = 0


async def read_byte(dut, bank, addr):
    set_bank_read(dut, bank, addr)
    await RisingEdge(dut.clk)
    dut.bank_en.value = 0
    await RisingEdge(dut.clk)
    return get_bank_rdata(dut, bank)


@cocotb.test()
async def test_write_read_single_bank(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await write_byte(dut, 0, 0x00, 0xAB)
    val = await read_byte(dut, 0, 0x00)
    assert val == 0xAB, f"expected 0xAB, got {val:#x}"


@cocotb.test()
async def test_write_read_multiple_addresses(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    for addr in range(16):
        await write_byte(dut, 0, addr, addr * 3)

    for addr in range(16):
        val = await read_byte(dut, 0, addr)
        expected = (addr * 3) & 0xFF
        assert val == expected, f"addr {addr}: expected {expected}, got {val}"


@cocotb.test()
async def test_independent_banks(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    for bank in range(NUM_BANKS):
        await write_byte(dut, bank, 0, 0x10 + bank)

    for bank in range(NUM_BANKS):
        val = await read_byte(dut, bank, 0)
        expected = 0x10 + bank
        assert val == expected, f"bank {bank}: expected {expected:#x}, got {val:#x}"


@cocotb.test()
async def test_concurrent_bank_writes(dut):
    """Write to all 8 banks simultaneously."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    en = 0xFF
    wen = 0xFF
    addr_packed = 0
    wdata_packed = 0
    for b in range(NUM_BANKS):
        addr_packed |= 5 << (b * ADDR_W)
        wdata_packed |= (0x50 + b) << (b * DATA_W)

    dut.bank_en.value = en
    dut.bank_wen.value = wen
    dut.bank_addr.value = addr_packed
    dut.bank_wdata.value = wdata_packed
    await RisingEdge(dut.clk)
    dut.bank_en.value = 0

    for bank in range(NUM_BANKS):
        val = await read_byte(dut, bank, 5)
        assert val == 0x50 + bank, f"bank {bank}: expected {0x50+bank:#x}, got {val:#x}"


def test_scratchpad_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "scratchpad.sv"],
        hdl_toplevel="scratchpad",
        build_dir=str(repo_root / "build" / "test_scratchpad"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="scratchpad",
        test_module="sim.test_scratchpad",
    )
