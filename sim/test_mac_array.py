"""Unit tests for mac_array: 16-lane tiled MAC with tile sequencing."""

import os
from pathlib import Path

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

try:
    from cocotb.runner import get_runner
except ModuleNotFoundError:
    from cocotb_tools.runner import get_runner


NUM_LANES = 16
PIPE_DRAIN = 2


def pack_lanes(values, width=8):
    """Pack a list of per-lane values into a single integer (lane 0 in LSBs)."""
    result = 0
    mask = (1 << width) - 1
    for i, v in enumerate(values):
        result |= (int(v) & mask) << (i * width)
    return result


def unpack_i32(packed, num=NUM_LANES):
    """Unpack 16 × INT32 from a wide integer, returning signed Python ints."""
    results = []
    mask32 = (1 << 32) - 1
    for i in range(num):
        raw = (packed >> (i * 32)) & mask32
        if raw >= (1 << 31):
            raw -= 1 << 32
        results.append(raw)
    return results


async def reset(dut, cycles=3):
    dut.rst_n.value = 0
    dut.tile_valid.value = 0
    dut.accum_mode.value = 0
    dut.tile_m.value = 0
    dut.tile_n.value = 0
    dut.tile_k.value = 0
    dut.a_data.value = 0
    dut.b_data.value = 0
    dut.a_valid.value = 0
    dut.b_valid.value = 0
    dut.result_ready.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def start_tile(dut, m, n, k, accum=False):
    dut.tile_valid.value = 1
    dut.tile_m.value = m
    dut.tile_n.value = n
    dut.tile_k.value = k
    dut.accum_mode.value = int(accum)
    await RisingEdge(dut.clk)
    dut.tile_valid.value = 0


async def feed_data(dut, a_vals, b_vals):
    """Feed one cycle of 16×INT8 operand pairs."""
    dut.a_data.value = pack_lanes(a_vals)
    dut.b_data.value = pack_lanes(b_vals)
    dut.a_valid.value = 1
    dut.b_valid.value = 1
    await RisingEdge(dut.clk)
    dut.a_valid.value = 0
    dut.b_valid.value = 0


async def wait_result(dut, timeout=200):
    dut.result_ready.value = 1
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.result_valid.value) == 1:
            raw = int(dut.result_data.value)
            return unpack_i32(raw)
    raise TimeoutError("result_valid never asserted")


# ── Tests ──


@cocotb.test()
async def test_idle_state(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    assert int(dut.tile_ready.value) == 1
    assert int(dut.busy.value) == 0
    assert int(dut.result_valid.value) == 0


@cocotb.test()
async def test_single_element(dut):
    """1×1×1 tile: lane 0 computes 3×7 = 21."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await start_tile(dut, m=1, n=1, k=1)
    a = [3] + [0] * 15
    b = [7] + [0] * 15
    await feed_data(dut, a, b)

    results = await wait_result(dut)
    assert results[0] == 21, f"lane 0: expected 21, got {results[0]}"


@cocotb.test()
async def test_dot_product_k4(dut):
    """1×1×4 tile: lane 0 computes dot product [1,2,3,4]·[5,6,7,8] = 70."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await start_tile(dut, m=1, n=1, k=4)
    a_vecs = [[1], [2], [3], [4]]
    b_vecs = [[5], [6], [7], [8]]
    for av, bv in zip(a_vecs, b_vecs):
        a = av + [0] * (16 - len(av))
        b = bv + [0] * (16 - len(bv))
        await feed_data(dut, a, b)

    results = await wait_result(dut)
    assert results[0] == 70, f"expected 70, got {results[0]}"


@cocotb.test()
async def test_parallel_lanes(dut):
    """1×4×2 tile: 4 lanes each compute a 2-element dot product."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # C[0][j] = A[0][0]*B[0][j] + A[0][1]*B[1][j] for j=0..3
    # A row = [2, 3], B = [[1,2,3,4],[5,6,7,8]]
    # C = [2*1+3*5, 2*2+3*6, 2*3+3*7, 2*4+3*8] = [17, 22, 27, 32]

    await start_tile(dut, m=1, n=4, k=2)
    # k=0: all lanes get A[0][0]=2, B[0][j]
    a0 = [2] * 4 + [0] * 12
    b0 = [1, 2, 3, 4] + [0] * 12
    await feed_data(dut, a0, b0)
    # k=1: all lanes get A[0][1]=3, B[1][j]
    a1 = [3] * 4 + [0] * 12
    b1 = [5, 6, 7, 8] + [0] * 12
    await feed_data(dut, a1, b1)

    results = await wait_result(dut)
    expected = [17, 22, 27, 32]
    for j in range(4):
        assert results[j] == expected[j], f"lane {j}: expected {expected[j]}, got {results[j]}"


@cocotb.test()
async def test_two_rows(dut):
    """2×2×2 tile: two rows, two lanes each."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # A = [[1,2],[3,4]], B = [[5,6],[7,8]]
    # C = [[1*5+2*7, 1*6+2*8], [3*5+4*7, 3*6+4*8]] = [[19,22],[43,50]]

    await start_tile(dut, m=2, n=2, k=2)

    # Row 0, k=0
    await feed_data(dut, [1, 1] + [0]*14, [5, 6] + [0]*14)
    # Row 0, k=1
    await feed_data(dut, [2, 2] + [0]*14, [7, 8] + [0]*14)

    r0 = await wait_result(dut)
    assert r0[0] == 19 and r0[1] == 22, f"row 0: {r0[:2]}"

    # Row 1, k=0
    await feed_data(dut, [3, 3] + [0]*14, [5, 6] + [0]*14)
    # Row 1, k=1
    await feed_data(dut, [4, 4] + [0]*14, [7, 8] + [0]*14)

    r1 = await wait_result(dut)
    assert r1[0] == 43 and r1[1] == 50, f"row 1: {r1[:2]}"


@cocotb.test()
async def test_backpressure(dut):
    """Result stalls when result_ready is low."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await start_tile(dut, m=1, n=1, k=1)
    await feed_data(dut, [10] + [0]*15, [10] + [0]*15)

    # Wait for drain but hold result_ready low
    dut.result_ready.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.result_valid.value) == 1:
            break

    assert int(dut.result_valid.value) == 1, "result_valid should be asserted"
    assert int(dut.tile_ready.value) == 0, "tile_ready should be low during output"

    # Now accept
    dut.result_ready.value = 1
    await RisingEdge(dut.clk)

    results = unpack_i32(int(dut.result_data.value))
    assert results[0] == 100, f"expected 100, got {results[0]}"


@cocotb.test()
async def test_signed_matmul(dut):
    """1×2×2 tile with signed operands."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # A = [-3, 5], B = [[4, -2], [1, 3]]
    # C = [(-3)*4 + 5*1, (-3)*(-2) + 5*3] = [-7, 21]

    await start_tile(dut, m=1, n=2, k=2)
    await feed_data(dut, [(-3) & 0xFF, (-3) & 0xFF] + [0]*14, [4, (-2) & 0xFF] + [0]*14)
    await feed_data(dut, [5, 5] + [0]*14, [1, 3] + [0]*14)

    results = await wait_result(dut)
    assert results[0] == -7, f"lane 0: expected -7, got {results[0]}"
    assert results[1] == 21, f"lane 1: expected 21, got {results[1]}"


@cocotb.test()
async def test_full_16_lanes(dut):
    """1×16×1 tile: all 16 lanes compute one product each."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    a_vals = list(range(1, 17))   # 1..16
    b_vals = list(range(1, 17))
    expected = [a * b for a, b in zip(a_vals, b_vals)]

    await start_tile(dut, m=1, n=16, k=1)
    await feed_data(dut, a_vals, b_vals)

    results = await wait_result(dut)
    for i in range(16):
        assert results[i] == expected[i], f"lane {i}: expected {expected[i]}, got {results[i]}"


@cocotb.test()
async def test_reference_matmul(dut):
    """4×4×4 tile verified against NumPy reference."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    rng = np.random.default_rng(42)
    A = rng.integers(-10, 10, size=(4, 4), dtype=np.int8)
    B = rng.integers(-10, 10, size=(4, 4), dtype=np.int8)
    C_ref = (A.astype(np.int32) @ B.astype(np.int32))

    await start_tile(dut, m=4, n=4, k=4)
    for row in range(4):
        for k in range(4):
            a_broadcast = [int(A[row, k]) & 0xFF] * 4 + [0] * 12
            b_col = [int(B[k, j]) & 0xFF for j in range(4)] + [0] * 12
            await feed_data(dut, a_broadcast, b_col)

        results = await wait_result(dut)
        for j in range(4):
            assert results[j] == int(C_ref[row, j]), \
                f"C[{row}][{j}]: expected {C_ref[row,j]}, got {results[j]}"


# ── pytest entry point ──


def test_mac_array_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[
            repo_root / "rtl" / "mac_lane.sv",
            repo_root / "rtl" / "mac_array.sv",
        ],
        hdl_toplevel="mac_array",
        build_dir=str(repo_root / "build" / "test_mac_array"),
        always=True,
        build_args=["--sv", "-Wno-MULTITOP"],
    )

    runner.test(
        hdl_toplevel="mac_array",
        test_module="sim.test_mac_array",
    )
