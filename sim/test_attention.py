import os
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import RisingEdge

from sim.reference_attention import attention


@cocotb.test()
async def attention_stub_smoke_test(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.reset.value = 1
    dut.valid_in.value = 0
    dut.query_in.value = 0
    dut.key_in.value = 0
    dut.value_in.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    query = np.array([[1.0]], dtype=np.float32)
    key = np.array([[1.0]], dtype=np.float32)
    value = np.array([[7.0]], dtype=np.float32)
    expected = attention(query, key, value)

    dut.valid_in.value = 1
    dut.query_in.value = int(query[0, 0])
    dut.key_in.value = int(key[0, 0])
    dut.value_in.value = int(value[0, 0])

    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)

    assert dut.valid_out.value.integer == 1
    assert dut.value_out.value.integer == int(value[0, 0])

    cocotb.log.info("Reference attention output: %s", expected.tolist())
    cocotb.log.info(
        "TODO: replace the pass-through checks with exact DUT/reference "
        "comparisons once the RTL implements real attention math."
    )


def test_attention_runner():
    repo_root = Path(__file__).resolve().parents[1]
    runner = get_runner(os.getenv("SIM", "verilator"))

    runner.build(
        sources=[repo_root / "rtl" / "attention_stub.sv"],
        hdl_toplevel="attention_stub",
        build_dir=str(repo_root / "build" / "cocotb"),
        always=True,
        build_args=["--sv"],
    )

    runner.test(
        hdl_toplevel="attention_stub",
        test_module="sim.test_attention",
        waves=True,
    )
