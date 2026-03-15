"""Unit tests for bank_arbiter: fixed-priority 3-requester arbitration."""

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


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    for sig in [dut.dma_req, dut.mac_req, dut.vec_req,
                dut.dma_wen, dut.mac_wen, dut.vec_wen,
                dut.dma_addr, dut.mac_addr, dut.vec_addr,
                dut.dma_wdata, dut.mac_wdata, dut.vec_wdata,
                dut.bank_rdata_i]:
        sig.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def set_req(sig_req, sig_addr, sig_wen, sig_wdata, bank, addr, wen=0, wdata=0):
    sig_req.value = int(sig_req.value) | (1 << bank)
    a = int(sig_addr.value)
    a &= ~(((1 << ADDR_W) - 1) << (bank * ADDR_W))
    a |= addr << (bank * ADDR_W)
    sig_addr.value = a
    if wen:
        sig_wen.value = int(sig_wen.value) | (1 << bank)
        d = int(sig_wdata.value)
        d &= ~(((1 << DATA_W) - 1) << (bank * DATA_W))
        d |= wdata << (bank * DATA_W)
        sig_wdata.value = d


@cocotb.test()
async def test_single_dma_request(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.dma_req.value = 1
    dut.dma_addr.value = 0x100
    dut.dma_wen.value = 1
    dut.dma_wdata.value = 0xAA
    await RisingEdge(dut.clk)

    assert int(dut.dma_grant.value) & 1 == 1
    assert int(dut.bank_en.value) & 1 == 1
    assert int(dut.bank_wen_o.value) & 1 == 1


@cocotb.test()
async def test_dma_beats_mac(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    bank = 2
    dut.dma_req.value = 1 << bank
    dut.mac_req.value = 1 << bank
    await RisingEdge(dut.clk)

    assert (int(dut.dma_grant.value) >> bank) & 1 == 1
    assert (int(dut.mac_grant.value) >> bank) & 1 == 0
    assert (int(dut.arb_conflict.value) >> bank) & 1 == 1


@cocotb.test()
async def test_mac_beats_vec(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    bank = 3
    dut.mac_req.value = 1 << bank
    dut.vec_req.value = 1 << bank
    await RisingEdge(dut.clk)

    assert (int(dut.mac_grant.value) >> bank) & 1 == 1
    assert (int(dut.vec_grant.value) >> bank) & 1 == 0
    assert (int(dut.arb_conflict.value) >> bank) & 1 == 1


@cocotb.test()
async def test_different_banks_no_conflict(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.dma_req.value = 1 << 0
    dut.mac_req.value = 1 << 1
    dut.vec_req.value = 1 << 2
    await RisingEdge(dut.clk)

    assert (int(dut.dma_grant.value) >> 0) & 1 == 1
    assert (int(dut.mac_grant.value) >> 1) & 1 == 1
    assert (int(dut.vec_grant.value) >> 2) & 1 == 1
    assert int(dut.arb_conflict.value) == 0


@cocotb.test()
async def test_read_data_routing(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    bank = 1
    dut.mac_req.value = 1 << bank
    await RisingEdge(dut.clk)
    assert (int(dut.mac_grant.value) >> bank) & 1 == 1

    dut.mac_req.value = 0
    dut.bank_rdata_i.value = 0xBE << (bank * DATA_W)
    await RisingEdge(dut.clk)

    mac_rd = (int(dut.mac_rdata.value) >> (bank * DATA_W)) & 0xFF
    dma_rd = (int(dut.dma_rdata.value) >> (bank * DATA_W)) & 0xFF
    assert mac_rd == 0xBE, f"mac_rdata: expected 0xBE, got {mac_rd:#x}"
    assert dma_rd == 0, f"dma_rdata should be 0, got {dma_rd:#x}"


def test_bank_arbiter_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "bank_arbiter.sv"],
        hdl_toplevel="bank_arbiter",
        build_dir=str(repo_root / "build" / "test_bank_arbiter"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="bank_arbiter",
        test_module="sim.test_bank_arbiter",
    )
