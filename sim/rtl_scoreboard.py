"""Reusable scoreboarding helpers for RTL-oriented cocotb tests.

The helpers in this module deliberately mirror the current integrated-core
behavior rather than the long-term architectural ideal. They provide exact
or near-exact references for the de-risked data path:

1. INT8 tile matmul with right-shift and optional saturation.
2. Fixed-point softmax using the vector unit's integer exp approximation.
3. A lightweight scoreboard object that stores stimulus, golden outputs,
   captured DUT outputs, and `ComparisonResult` verdicts.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np

from sim.reference_attention import ComparisonResult, compare

EXP_LUT = np.array(
    [256, 94, 35, 13, 5, 2, 1] + [0] * 10,
    dtype=np.int32,
)


def saturate_int8(values: np.ndarray) -> np.ndarray:
    return np.clip(values, -128, 127).astype(np.int8)


def matmul_tile(
    lhs: np.ndarray,
    rhs: np.ndarray,
    *,
    shift: int = 0,
    saturate: bool = True,
) -> np.ndarray:
    """Golden model for the current compute engine contract.

    `lhs` is MxK, `rhs` is KxN, and the returned tile is MxN INT8.
    """
    acc = lhs.astype(np.int32) @ rhs.astype(np.int32)
    if shift > 0:
        acc = acc >> shift
    if saturate:
        return saturate_int8(acc)
    return acc.astype(np.int8)


def softmax_fixed(scores: np.ndarray) -> np.ndarray:
    """Golden model for the current vector unit.

    The output is an INT8 matrix whose rows sum to approximately 127.
    """
    scores_i32 = scores.astype(np.int32)
    out = np.zeros_like(scores_i32, dtype=np.uint8)

    for row_idx, row in enumerate(scores_i32):
        row_max = int(np.max(row))
        exp_vals = []
        for raw in row:
            shifted = int(raw) - row_max
            if shifted >= 0:
                exp_vals.append(256)
            else:
                magnitude = min(-shifted, len(EXP_LUT) - 1)
                exp_vals.append(int(EXP_LUT[magnitude]))

        row_sum = sum(exp_vals)
        if row_sum == 0:
            continue

        scaled = []
        for exp_val in exp_vals:
            value = (exp_val * 127 + (row_sum // 2)) // row_sum
            scaled.append(min(value, 127))

        out[row_idx, :] = np.array(scaled, dtype=np.uint8)

    return out


def descriptor(
    opcode: int,
    *,
    flags: int = 0,
    dst: int = 0,
    src: int = 0,
    m: int = 0,
    n: int = 0,
    k: int = 0,
    tag: int = 0,
) -> int:
    return (
        ((opcode & 0xFF) << 56)
        | ((flags & 0xFF) << 48)
        | ((dst & 0xFF) << 40)
        | ((src & 0xFF) << 32)
        | ((m & 0xFF) << 24)
        | ((n & 0xFF) << 16)
        | ((k & 0xFF) << 8)
        | ((tag & 0xF) << 4)
    )


@dataclass
class Scoreboard:
    input_stimulus: dict[str, Any] = field(default_factory=dict)
    golden_outputs: dict[str, np.ndarray] = field(default_factory=dict)
    dut_outputs: dict[str, np.ndarray] = field(default_factory=dict)
    comparison_results: dict[str, ComparisonResult] = field(default_factory=dict)

    def record(self, name: str, golden: np.ndarray, dut: np.ndarray, **thresholds: Any) -> None:
        golden_arr = np.asarray(golden, dtype=np.float64)
        dut_arr = np.asarray(dut, dtype=np.float64)
        self.golden_outputs[name] = np.asarray(golden)
        self.dut_outputs[name] = np.asarray(dut)
        self.comparison_results[name] = compare(golden_arr, dut_arr, **thresholds)

    @property
    def pass_fail_summary(self) -> dict[str, bool]:
        return {name: result.passed for name, result in self.comparison_results.items()}

    def assert_passed(self) -> None:
        failures = [f"{name}: {result.detail}" for name, result in self.comparison_results.items() if not result.passed]
        assert not failures, "\n".join(failures)
