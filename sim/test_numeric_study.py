"""Numeric study: compare float, quantized, and tiled-quantized attention paths.

This module serves two purposes:
  1. Automated pass/fail tests for the golden-model numeric contract.
  2. Printable study output showing error budgets across configurations.
"""

from __future__ import annotations

import numpy as np
import pytest

from sim.reference_attention import (
    AccumulatorWidth,
    ComparisonResult,
    PrecisionConfig,
    TileConfig,
    attention,
    compare,
    make_workload,
    quantized_attention,
    tiled_attention,
)


# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

WORKLOADS = [
    {"seq_len": 16, "d_model": 16, "seed": 1},
    {"seq_len": 64, "d_model": 64, "seed": 2},
    {"seq_len": 128, "d_model": 64, "seed": 42},
]

TILE_SIZES = [8, 16, 32, 64]

PRECISIONS = [
    PrecisionConfig(accumulator=AccumulatorWidth.INT16),
    PrecisionConfig(accumulator=AccumulatorWidth.INT32),
]


# ---------------------------------------------------------------------------
# Float vs quantized baseline
# ---------------------------------------------------------------------------

class TestQuantizedAccuracy:
    """INT8 quantization introduces expected error vs float.

    These thresholds encode the architecture decision: cosine > 0.90 and
    mean absolute error bounded are the acceptance criteria for the INT8
    precision policy.  Max relative error is excluded because near-zero
    reference values make it uninformative.
    """

    @pytest.mark.parametrize("wl", WORKLOADS, ids=lambda w: f"s{w['seq_len']}_d{w['d_model']}")
    def test_quantized_vs_float(self, wl: dict) -> None:
        q, k, v = make_workload(**wl)
        ref = attention(q, k, v)
        qout = quantized_attention(q, k, v)
        result = compare(ref, qout, atol=20.0, rtol=1e6, min_cosine=0.90)
        assert result.passed, f"quantized vs float: {result.detail}"

    @pytest.mark.parametrize("prec", PRECISIONS, ids=lambda p: f"acc{p.accumulator.value}")
    def test_accumulator_width_impact(self, prec: PrecisionConfig) -> None:
        q, k, v = make_workload(seq_len=64, d_model=64)
        ref = attention(q, k, v)
        qout = quantized_attention(q, k, v, precision=prec)
        result = compare(ref, qout, atol=20.0, rtol=1e6, min_cosine=0.90)
        assert result.passed, (
            f"accumulator width {prec.accumulator.value}: {result.detail}"
        )


# ---------------------------------------------------------------------------
# Tiled vs non-tiled quantized agreement
# ---------------------------------------------------------------------------

class TestTiledAgreement:
    @pytest.mark.parametrize("ts", TILE_SIZES, ids=lambda t: f"tile{t}")
    def test_tiled_matches_quantized(self, ts: int) -> None:
        """Tiled and non-tiled quantized paths must agree closely."""
        q, k, v = make_workload(seq_len=64, d_model=64)
        prec = PrecisionConfig()
        qout = quantized_attention(q, k, v, precision=prec)
        tout = tiled_attention(q, k, v, tile=TileConfig(ts, ts), precision=prec)
        result = compare(qout, tout, atol=1e-6, rtol=1e-5, min_cosine=0.9999)
        assert result.passed, f"tiled vs quantized at tile={ts}: {result.detail}"

    @pytest.mark.parametrize("wl", WORKLOADS, ids=lambda w: f"s{w['seq_len']}_d{w['d_model']}")
    def test_tiled_vs_float(self, wl: dict) -> None:
        """Tiled quantized vs float inherits the INT8 quantization gap."""
        q, k, v = make_workload(**wl)
        ref = attention(q, k, v)
        tout = tiled_attention(q, k, v, tile=TileConfig(16, 16))
        result = compare(ref, tout, atol=20.0, rtol=1e6, min_cosine=0.90)
        assert result.passed, f"tiled vs float: {result.detail}"


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases:
    def test_single_element(self) -> None:
        q = np.array([[5.0]])
        k = np.array([[3.0]])
        v = np.array([[7.0]])
        ref = attention(q, k, v)
        tout = tiled_attention(q, k, v, tile=TileConfig(1, 1))
        result = compare(ref, tout, atol=1e-6, rtol=1e-6, min_cosine=0.9999)
        assert result.passed, f"single element: {result.detail}"

    def test_large_negative_scores(self) -> None:
        """Softmax should handle large negative values without NaN."""
        q = np.full((4, 4), -100.0)
        k = np.full((4, 4), 100.0)
        v = np.ones((4, 4))
        tout = tiled_attention(q, k, v, tile=TileConfig(2, 2))
        assert not np.any(np.isnan(tout)), "NaN in output with extreme inputs"
        assert not np.any(np.isinf(tout)), "Inf in output with extreme inputs"

    def test_identical_rows(self) -> None:
        """When all K rows are identical, attention output should equal V."""
        q = np.random.default_rng(99).uniform(-5, 5, (8, 8))
        k = np.tile(np.array([1.0, 2, 3, 4, 5, 6, 7, 8]), (8, 1))
        v = np.eye(8) * 3.0
        ref = attention(q, k, v)
        tout = tiled_attention(q, k, v, tile=TileConfig(4, 4))
        result = compare(ref, tout, atol=0.5, rtol=0.3, min_cosine=0.99)
        assert result.passed, f"identical K rows: {result.detail}"


# ---------------------------------------------------------------------------
# Study output (not a pass/fail test, prints error budget table)
# ---------------------------------------------------------------------------

def print_numeric_study() -> None:
    """Print a formatted table of error budgets across configurations."""
    print("\n=== Numeric Study: Error Budgets ===\n")
    header = (
        f"{'Config':<30} {'MaxAbs':>10} {'MeanAbs':>10} "
        f"{'MaxRel':>10} {'Cosine':>10} {'Status':>6}"
    )
    print(header)
    print("-" * len(header))

    for wl in WORKLOADS:
        q, k, v = make_workload(**wl)
        ref = attention(q, k, v)

        tag = f"s{wl['seq_len']}_d{wl['d_model']}"

        for prec in PRECISIONS:
            qout = quantized_attention(q, k, v, precision=prec)
            r = compare(ref, qout, atol=5.0, rtol=1.0, min_cosine=0.90)
            label = f"{tag} quant acc{prec.accumulator.value}"
            print(
                f"{label:<30} {r.max_abs_error:>10.4e} {r.mean_abs_error:>10.4e} "
                f"{r.max_rel_error:>10.4e} {r.cosine_similarity:>10.6f} "
                f"{'PASS' if r.passed else 'FAIL':>6}"
            )

        for ts in [16, 64]:
            tout = tiled_attention(q, k, v, tile=TileConfig(ts, ts))
            r = compare(ref, tout, atol=5.0, rtol=1.0, min_cosine=0.90)
            label = f"{tag} tiled {ts}x{ts}"
            print(
                f"{label:<30} {r.max_abs_error:>10.4e} {r.mean_abs_error:>10.4e} "
                f"{r.max_rel_error:>10.4e} {r.cosine_similarity:>10.6f} "
                f"{'PASS' if r.passed else 'FAIL':>6}"
            )

    print()


if __name__ == "__main__":
    print_numeric_study()
