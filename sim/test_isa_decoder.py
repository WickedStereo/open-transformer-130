"""Unit tests for isa_decoder: 64-bit descriptor decode and fault detection."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


def make_descriptor(opcode, flags=0, dst=0, src=0, m=0, n=0, k=0, tag=0, reserved=0):
    """Build a 64-bit command descriptor."""
    return ((opcode & 0xFF) << 56 |
            (flags & 0xFF) << 48 |
            (dst & 0xFF) << 40 |
            (src & 0xFF) << 32 |
            (m & 0xFF) << 24 |
            (n & 0xFF) << 16 |
            (k & 0xFF) << 8 |
            (tag & 0xF) << 4 |
            (reserved & 0xF))


ACT_NOP = 0; ACT_DMA = 1; ACT_COMPUTE = 2; ACT_VECTOR = 3
ACT_CONFIG = 4; ACT_BARRIER = 5


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.desc_valid.value = 0
    dut.desc_data.value = 0
    dut.action_ready.value = 0
    dut.default_m.value = 64
    dut.default_n.value = 64
    dut.default_k.value = 64
    dut.fault_clear.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def decode_one(dut, descriptor, ready=True):
    """Present a descriptor and wait for the decoded action or fault."""
    dut.desc_valid.value = 1
    dut.desc_data.value = descriptor
    dut.action_ready.value = int(ready)
    await RisingEdge(dut.clk)  # decoder transitions from IDLE
    dut.desc_valid.value = 0

    # Wait for action_valid or fault_valid
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.action_valid.value) == 1 or int(dut.fault_active.value) == 1:
            break

    return {
        "action_valid": int(dut.action_valid.value),
        "action_type": int(dut.action_type.value),
        "fault_valid": int(dut.fault_active.value),
    }


@cocotb.test()
async def test_nop_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x00)
    r = await decode_one(dut, desc)
    assert r["action_valid"] == 1
    assert r["action_type"] == ACT_NOP


@cocotb.test()
async def test_load_tile_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x01, dst=5, m=16, n=16)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_DMA
    assert int(dut.action_load.value) == 1
    assert int(dut.action_dst_slot.value) == 5


@cocotb.test()
async def test_store_tile_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x02, src=3, m=32, n=32)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_DMA
    assert int(dut.action_load.value) == 0
    assert int(dut.action_src_slot.value) == 3


@cocotb.test()
async def test_matmul_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x03, src=1, dst=2, m=4, n=4, k=4, flags=0x80)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_COMPUTE
    assert int(dut.action_dim_m.value) == 4
    assert int(dut.action_dim_k.value) == 4
    assert int(dut.action_flags.value) & 0x80  # accum flag


@cocotb.test()
async def test_softmax_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x05, src=10, dst=11, m=64, n=64, flags=0x80)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_VECTOR


@cocotb.test()
async def test_config_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x06, flags=0x02, m=128, n=0)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_CONFIG


@cocotb.test()
async def test_barrier_decode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x07, flags=0x80)
    r = await decode_one(dut, desc)
    assert r["action_type"] == ACT_BARRIER


@cocotb.test()
async def test_fault_invalid_opcode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x08)
    dut.desc_valid.value = 1
    dut.desc_data.value = desc
    dut.action_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fault_valid.value) == 1 or int(dut.fault_active.value) == 1


@cocotb.test()
async def test_fault_reserved_field(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x00, reserved=0x1)
    dut.desc_valid.value = 1
    dut.desc_data.value = desc
    dut.action_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fault_valid.value) == 1 or int(dut.fault_active.value) == 1


@cocotb.test()
async def test_fault_tile_oob(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    desc = make_descriptor(opcode=0x01, dst=32)  # slot 32 is OOB
    dut.desc_valid.value = 1
    dut.desc_data.value = desc
    dut.action_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fault_valid.value) == 1 or int(dut.fault_active.value) == 1


@cocotb.test()
async def test_fault_clear(dut):
    """After fault, clearing restores normal operation."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Trigger fault
    desc = make_descriptor(opcode=0xFF)
    r = await decode_one(dut, desc)
    assert r["fault_valid"] == 1, "fault should be active"

    # Clear fault
    dut.fault_clear.value = 1
    await RisingEdge(dut.clk)
    dut.fault_clear.value = 0
    await RisingEdge(dut.clk)

    assert int(dut.fault_active.value) == 0


@cocotb.test()
async def test_default_dimension_resolution(dut):
    """dim_m=0 should resolve to the configured default."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.default_m.value = 32
    dut.default_n.value = 16
    dut.default_k.value = 8

    desc = make_descriptor(opcode=0x03, src=0, dst=1, m=0, n=0, k=0)
    r = await decode_one(dut, desc)
    assert int(dut.action_dim_m.value) == 32
    assert int(dut.action_dim_n.value) == 16
    assert int(dut.action_dim_k.value) == 8


def test_isa_decoder_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "isa_decoder.sv"],
        hdl_toplevel="isa_decoder",
        build_dir=str(repo_root / "build" / "test_isa_decoder"),
        always=True,
        build_args=["--sv", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="isa_decoder",
        test_module="sim.test_isa_decoder",
    )
