"""Unit tests for dma_engine."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner

NUM_BANKS = 8
ADDR_W = 14
DATA_W = 8


def unpack_addrs(packed: int, bank: int) -> int:
    return (packed >> (bank * ADDR_W)) & ((1 << ADDR_W) - 1)


def unpack_data(packed: int, bank: int) -> int:
    return (packed >> (bank * DATA_W)) & 0xFF


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.cmd_valid.value = 0
    dut.cmd_load.value = 0
    dut.cmd_host_addr.value = 0
    dut.cmd_slot_id.value = 0
    dut.cmd_byte_count.value = 0
    dut.bus_rdata.value = 0
    dut.bus_ack.value = 0
    dut.scratch_grant.value = 0
    dut.scratch_rdata.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def serve_bus(dut, memory, timeout=500):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        dut.bus_ack.value = 0
        if int(dut.bus_req.value):
            addr = int(dut.bus_addr.value)
            if int(dut.bus_wen.value):
                payload = int(dut.bus_wdata.value)
                for i in range(16):
                    memory[addr + i] = (payload >> (i * 8)) & 0xFF
            else:
                packed = 0
                for i in range(16):
                    packed |= memory.get(addr + i, 0) << (i * 8)
                dut.bus_rdata.value = packed
            dut.bus_ack.value = 1


async def serve_scratch(dut, memory, timeout=1500):
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


async def issue_cmd(dut, *, load, host_addr, slot_id, byte_count):
    dut.cmd_valid.value = 1
    dut.cmd_load.value = int(load)
    dut.cmd_host_addr.value = host_addr
    dut.cmd_slot_id.value = slot_id
    dut.cmd_byte_count.value = byte_count
    await RisingEdge(dut.clk)
    dut.cmd_valid.value = 0


@cocotb.test()
async def test_load_moves_host_bytes_into_scratchpad(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    host_mem = {0x100 + i: (i * 11) & 0xFF for i in range(20)}
    scratch_mem = {}
    cocotb.start_soon(serve_bus(dut, host_mem))
    cocotb.start_soon(serve_scratch(dut, scratch_mem))

    await issue_cmd(dut, load=True, host_addr=0x100, slot_id=0, byte_count=20)

    for _ in range(400):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    assert int(dut.done.value) == 1
    assert int(dut.bytes_moved.value) == 20
    for i in range(20):
        assert scratch_mem.get(i, None) == host_mem[0x100 + i]


@cocotb.test()
async def test_store_moves_scratchpad_bytes_to_host(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    host_mem = {}
    scratch_mem = {i: (0x40 + i) & 0xFF for i in range(20)}
    cocotb.start_soon(serve_bus(dut, host_mem))
    cocotb.start_soon(serve_scratch(dut, scratch_mem))

    await issue_cmd(dut, load=False, host_addr=0x200, slot_id=0, byte_count=20)

    for _ in range(600):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break

    assert int(dut.done.value) == 1
    assert int(dut.bytes_moved.value) == 20
    for i in range(20):
        assert host_mem.get(0x200 + i, None) == scratch_mem[i]


@cocotb.test()
async def test_invalid_transfer_size_raises_error(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await issue_cmd(dut, load=True, host_addr=0, slot_id=0, byte_count=4097)
    await RisingEdge(dut.clk)

    assert int(dut.error.value) == 1


def test_dma_engine_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "dma_engine.sv"],
        hdl_toplevel="dma_engine",
        build_dir=str(repo_root / "build" / "test_dma_engine"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="dma_engine",
        test_module="sim.test_dma_engine",
    )
