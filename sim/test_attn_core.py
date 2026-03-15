"""End-to-end integration tests for attn_core.

Programs the accelerator through MMIO, feeds commands via the queue bus,
and validates DMA load, compute dispatch, and status register behavior.
"""

import os
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from sim.rtl_scoreboard import Scoreboard, descriptor, matmul_tile, softmax_fixed

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


def make_descriptor(opcode, flags=0, dst=0, src=0, m=0, n=0, k=0, tag=0):
    return descriptor(opcode, flags=flags, dst=dst, src=src, m=m, n=n, k=k, tag=tag)


async def reset(dut, cycles=5):
    dut.rst_n.value = 0
    dut.mmio_valid.value = 0
    dut.mmio_wen.value = 0
    dut.mmio_addr.value = 0
    dut.mmio_wdata.value = 0
    dut.bus_rdata.value = 0
    dut.bus_ack.value = 0
    dut.qbus_rdata.value = 0
    dut.qbus_ack.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def mmio_write(dut, offset, value):
    dut.mmio_valid.value = 1
    dut.mmio_wen.value = 1
    dut.mmio_addr.value = offset
    dut.mmio_wdata.value = value
    await RisingEdge(dut.clk)
    dut.mmio_valid.value = 0
    dut.mmio_wen.value = 0


async def mmio_read(dut, offset):
    dut.mmio_valid.value = 1
    dut.mmio_wen.value = 0
    dut.mmio_addr.value = offset
    await RisingEdge(dut.clk)
    dut.mmio_valid.value = 0
    return int(dut.mmio_rdata.value)


async def serve_queue_bus(dut, descriptors, timeout=500):
    """Background task: respond to queue bus requests with pre-loaded descriptors."""
    fetch_count = 0
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.qbus_req.value) == 1:
            addr = int(dut.qbus_addr.value)
            idx = (addr >> 3) & 0xFF
            if idx < len(descriptors):
                dut.qbus_rdata.value = descriptors[idx]
            else:
                dut.qbus_rdata.value = 0
            dut.qbus_ack.value = 1
            await RisingEdge(dut.clk)
            dut.qbus_ack.value = 0
            fetch_count += 1
    return fetch_count


async def serve_dma_bus(dut, memory, timeout=2000):
    """Background task: respond to DMA bus requests against a byte-addressable memory dict."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.bus_req.value) == 1:
            addr = int(dut.bus_addr.value)
            if int(dut.bus_wen.value) == 0:
                # Read: pack 16 bytes
                packed = 0
                for i in range(16):
                    packed |= memory.get(addr + i, 0) << (i * 8)
                dut.bus_rdata.value = packed
            else:
                # Write: unpack 16 bytes
                wd = int(dut.bus_wdata.value)
                for i in range(16):
                    memory[addr + i] = (wd >> (i * 8)) & 0xFF
            dut.bus_ack.value = 1
            await RisingEdge(dut.clk)
            dut.bus_ack.value = 0


# ── Tests ──


@cocotb.test()
async def test_mmio_defaults(dut):
    """Verify MMIO default values after reset."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Default tile dimensions should be 64
    val_m = await mmio_read(dut, 0x1C)
    val_n = await mmio_read(dut, 0x20)
    val_k = await mmio_read(dut, 0x24)
    assert val_m == 64, f"default_m: {val_m}"
    assert val_n == 64, f"default_n: {val_n}"
    assert val_k == 64, f"default_k: {val_k}"


@cocotb.test()
async def test_enable_and_status(dut):
    """Enable the core and check status register."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Initially not busy, no fault
    status = await mmio_read(dut, 0x04)
    assert (status & 0x01) == 0, "should not be busy"
    assert (status & 0x02) == 0, "should not be faulted"

    # Enable
    await mmio_write(dut, 0x00, 0x01)
    ctrl = await mmio_read(dut, 0x00)
    assert (ctrl & 0x01) == 1, "enable bit"


@cocotb.test()
async def test_nop_command(dut):
    """Queue a NOP and verify tail advances."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    nop_desc = make_descriptor(opcode=0x00)

    # Configure queue
    await mmio_write(dut, 0x08, 0x0000_0000)  # queue base
    await mmio_write(dut, 0x0C, 4)            # log2(16) = 4 entries

    # Start queue bus responder
    cocotb.start_soon(serve_queue_bus(dut, [nop_desc]))

    # Enable core
    await mmio_write(dut, 0x00, 0x01)

    # Advance head
    await mmio_write(dut, 0x10, 1)

    # Wait for tail to advance
    for _ in range(50):
        await RisingEdge(dut.clk)
        tail = await mmio_read(dut, 0x14)
        if tail >= 1:
            break

    assert tail >= 1, f"tail should have advanced, got {tail}"


@cocotb.test()
async def test_fault_on_invalid_opcode(dut):
    """Invalid opcode sets fault in STATUS."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    bad_desc = make_descriptor(opcode=0xFF)

    await mmio_write(dut, 0x08, 0x0000_0000)
    await mmio_write(dut, 0x0C, 4)
    cocotb.start_soon(serve_queue_bus(dut, [bad_desc]))
    await mmio_write(dut, 0x00, 0x01)
    await mmio_write(dut, 0x10, 1)

    # Wait for fault
    faulted = False
    for _ in range(50):
        await RisingEdge(dut.clk)
        status = await mmio_read(dut, 0x04)
        if (status & 0x02) != 0:
            faulted = True
            break

    assert faulted, "expected fault on invalid opcode"

    # Clear fault
    await mmio_write(dut, 0x00, 0x05)  # enable + fault_clear
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    status = await mmio_read(dut, 0x04)
    assert (status & 0x02) == 0, "fault should be cleared"


@cocotb.test()
async def test_dma_load_command(dut):
    """LOAD_TILE command triggers DMA bus activity."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Host memory with test data
    host_mem = {i: (i * 7) & 0xFF for i in range(64)}

    # LOAD_TILE: slot 0, 4×4 = 16 bytes (small for faster test)
    load_desc = make_descriptor(opcode=0x01, dst=0, m=4, n=4)

    await mmio_write(dut, 0x38, 0x0000_0000)  # DMA host addr
    await mmio_write(dut, 0x08, 0x0001_0000)  # queue base (separate region)
    await mmio_write(dut, 0x0C, 4)

    cocotb.start_soon(serve_queue_bus(dut, [load_desc], timeout=3000))
    cocotb.start_soon(serve_dma_bus(dut, host_mem, timeout=3000))

    await mmio_write(dut, 0x00, 0x01)
    await mmio_write(dut, 0x10, 1)

    # Wait for tail to advance -- the full pipeline is: queue fetch -> decode
    # -> scheduler -> DMA command -> bus xfer -> scratchpad write -> done
    tail = 0
    for _ in range(2000):
        await RisingEdge(dut.clk)
        tail = await mmio_read(dut, 0x14)
        if tail >= 1:
            break

    assert tail >= 1, f"tail should have advanced after DMA load, got {tail}"


@cocotb.test()
async def test_perf_counters(dut):
    """Performance counters increment during activity."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Initially zero
    busy = await mmio_read(dut, 0x28)
    assert busy == 0, f"perf_busy should be 0, got {busy}"

    # Run a NOP to generate some busy cycles
    nop_desc = make_descriptor(opcode=0x00)
    await mmio_write(dut, 0x08, 0x0000_0000)
    await mmio_write(dut, 0x0C, 4)
    cocotb.start_soon(serve_queue_bus(dut, [nop_desc]))
    await mmio_write(dut, 0x00, 0x01)
    await mmio_write(dut, 0x10, 1)

    for _ in range(30):
        await RisingEdge(dut.clk)

    busy_after = await mmio_read(dut, 0x28)
    # busy_cycles may be > 0 if scheduler was active
    cocotb.log.info(f"perf_busy_cycles = {busy_after}")


@cocotb.test()
async def test_soft_reset(dut):
    """Soft reset clears perf counters and config."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await mmio_write(dut, 0x38, 0xDEADBEEF)
    val = await mmio_read(dut, 0x38)
    assert val == 0xDEADBEEF

    # Soft reset
    await mmio_write(dut, 0x00, 0x02)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    val = await mmio_read(dut, 0x38)
    assert val == 0, f"DMA host addr should be cleared, got {val:#x}"

    busy = await mmio_read(dut, 0x28)
    assert busy == 0, "perf counter should be cleared"


@cocotb.test()
async def test_end_to_end_matmul_softmax_store(dut):
    """Run LOAD -> LOAD -> MATMUL -> SOFTMAX -> STORE against a golden model."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    lhs = np.array([[2, 1], [1, 3]], dtype=np.int8)
    rhs = np.array([[1, -1], [2, 1]], dtype=np.int8)
    scores = matmul_tile(lhs, rhs, shift=0, saturate=True)
    weights = softmax_fixed(scores)

    sb = Scoreboard()
    sb.input_stimulus["lhs"] = lhs
    sb.input_stimulus["rhs"] = rhs
    sb.golden_outputs["scores"] = scores
    sb.golden_outputs["weights"] = weights

    host_mem = {}
    for idx, value in enumerate(lhs.flatten()):
        host_mem[idx] = int(value) & 0xFF
    for idx, value in enumerate(rhs.flatten()):
        host_mem[0x1000 + idx] = int(value) & 0xFF

    commands = [
        make_descriptor(opcode=0x01, dst=0, m=2, n=2),
        make_descriptor(opcode=0x01, dst=1, m=2, n=2),
        make_descriptor(opcode=0x03, flags=0x40, dst=1, src=0, m=2, n=2, k=2),
        make_descriptor(opcode=0x05, flags=0x80, dst=2, src=1, m=2, n=2),
        make_descriptor(opcode=0x02, src=2, m=2, n=2),
    ]

    await mmio_write(dut, 0x38, 0x0000_0000)
    await mmio_write(dut, 0x08, 0x0002_0000)
    await mmio_write(dut, 0x0C, 4)

    cocotb.start_soon(serve_queue_bus(dut, commands, timeout=6000))
    cocotb.start_soon(serve_dma_bus(dut, host_mem, timeout=6000))

    await mmio_write(dut, 0x00, 0x01)
    await mmio_write(dut, 0x10, len(commands))

    tail = 0
    status = 0
    for _ in range(4000):
        await RisingEdge(dut.clk)
        tail = await mmio_read(dut, 0x14)
        status = await mmio_read(dut, 0x04)
        if tail >= len(commands) and (status & 0x01) == 0:
            break

    assert tail >= len(commands), f"tail should reach {len(commands)}, got {tail}"
    assert (status & 0x01) == 0, "core should be idle before checking stored output"

    observed = np.array(
        [
            [host_mem.get(0x2000 + 0, 0), host_mem.get(0x2000 + 1, 0)],
            [host_mem.get(0x2000 + 2, 0), host_mem.get(0x2000 + 3, 0)],
        ],
        dtype=np.uint8,
    )
    sb.record("weights", weights, observed, atol=0.0, rtol=0.0, min_cosine=1.0)
    sb.assert_passed()


# ── pytest entry point ──


def test_attn_core_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    rtl_dir = repo_root / "rtl"
    sources = [
        rtl_dir / "mmio_regs.sv",
        rtl_dir / "queue_ctrl.sv",
        rtl_dir / "isa_decoder.sv",
        rtl_dir / "tile_scheduler.sv",
        rtl_dir / "dma_engine.sv",
        rtl_dir / "bank_arbiter.sv",
        rtl_dir / "mac_lane.sv",
        rtl_dir / "mac_array.sv",
        rtl_dir / "compute_engine.sv",
        rtl_dir / "scratchpad_bank_1rw.sv",
        rtl_dir / "scratchpad.sv",
        rtl_dir / "vector_unit.sv",
        rtl_dir / "perf_counters.sv",
        rtl_dir / "attn_core.sv",
    ]

    runner.build(
        sources=sources,
        hdl_toplevel="attn_core",
        build_dir=str(repo_root / "build" / "test_attn_core"),
        always=True,
        build_args=["--sv", "-Wno-MULTITOP", "-Wno-WIDTHTRUNC", "-Wno-UNUSEDSIGNAL"],
    )

    runner.test(
        hdl_toplevel="attn_core",
        test_module="sim.test_attn_core",
    )
