"""Golden reference model for attention with tiled execution and quantization.

Provides three levels of fidelity:
  1. Float reference  -- canonical fp64 attention for ground truth.
  2. Quantized reference -- INT8 operands with configurable accumulator width,
     matching the hardware precision policy.
  3. Tiled quantized reference -- tiled execution with online softmax,
     matching the hardware dataflow and tile scheduling.

Numeric comparison utilities let verification code express pass/fail in terms
of absolute error, relative error, and cosine similarity.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence

import numpy as np


# ---------------------------------------------------------------------------
# Precision configuration
# ---------------------------------------------------------------------------

class AccumulatorWidth(Enum):
    INT16 = 16
    INT32 = 32


@dataclass(frozen=True)
class PrecisionConfig:
    """Hardware-matching precision policy."""
    input_bits: int = 8
    accumulator: AccumulatorWidth = AccumulatorWidth.INT32
    softmax_internal_bits: int = 16
    scale_shift: int = 0  # right-shift applied after matmul accumulation

    @property
    def input_range(self) -> tuple[int, int]:
        half = 1 << (self.input_bits - 1)
        return (-half, half - 1)

    @property
    def accum_range(self) -> tuple[int, int]:
        half = 1 << (self.accumulator.value - 1)
        return (-half, half - 1)


DEFAULT_PRECISION = PrecisionConfig()


# ---------------------------------------------------------------------------
# Float reference (ground truth)
# ---------------------------------------------------------------------------

def softmax(values: np.ndarray, axis: int = -1) -> np.ndarray:
    shifted = values - np.max(values, axis=axis, keepdims=True)
    exp_values = np.exp(shifted)
    return exp_values / np.sum(exp_values, axis=axis, keepdims=True)


def attention(query: np.ndarray, key: np.ndarray, value: np.ndarray) -> np.ndarray:
    scale = np.sqrt(query.shape[-1])
    scores = (query @ key.T) / scale
    weights = softmax(scores, axis=-1)
    return weights @ value


# ---------------------------------------------------------------------------
# Quantization helpers
# ---------------------------------------------------------------------------

def quantize(x: np.ndarray, bits: int = 8) -> np.ndarray:
    half = 1 << (bits - 1)
    lo, hi = -half, half - 1
    return np.clip(np.round(x), lo, hi).astype(np.int32)


def saturate(x: np.ndarray, bits: int) -> np.ndarray:
    half = 1 << (bits - 1)
    return np.clip(x, -half, half - 1)


def int_matmul(
    a: np.ndarray,
    b: np.ndarray,
    accum_bits: int = 32,
) -> np.ndarray:
    """Integer matmul with bounded accumulation, matching MAC array behavior."""
    a32 = a.astype(np.int64)
    b32 = b.astype(np.int64)
    result = a32 @ b32
    return saturate(result, accum_bits).astype(np.int32)


# ---------------------------------------------------------------------------
# Quantized (non-tiled) attention
# ---------------------------------------------------------------------------

def quantized_attention(
    query: np.ndarray,
    key: np.ndarray,
    value: np.ndarray,
    precision: PrecisionConfig = DEFAULT_PRECISION,
) -> np.ndarray:
    """Attention with INT8 inputs and integer accumulation.

    Softmax is computed in float on the integer scores -- hardware will use a
    fixed-point approximation, but this path establishes the numerically
    correct quantized baseline.
    """
    q = quantize(query, precision.input_bits)
    k = quantize(key, precision.input_bits)
    v = quantize(value, precision.input_bits)

    scores = int_matmul(q, k.T, precision.accumulator.value)
    if precision.scale_shift > 0:
        scores = scores >> precision.scale_shift

    weights = softmax(scores.astype(np.float64), axis=-1)

    out = weights @ v.astype(np.float64)
    return out


# ---------------------------------------------------------------------------
# Tiled execution with online softmax
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TileConfig:
    """Tile geometry for hardware-matching tiled execution."""
    tile_m: int = 64
    tile_n: int = 64

    @property
    def shape(self) -> tuple[int, int]:
        return (self.tile_m, self.tile_n)


DEFAULT_TILE = TileConfig()


def _tile_ranges(total: int, tile: int) -> list[tuple[int, int]]:
    """Produce (start, end) pairs covering [0, total) in chunks of tile."""
    ranges = []
    for start in range(0, total, tile):
        end = min(start + tile, total)
        ranges.append((start, end))
    return ranges


def tiled_attention(
    query: np.ndarray,
    key: np.ndarray,
    value: np.ndarray,
    tile: TileConfig = DEFAULT_TILE,
    precision: PrecisionConfig = DEFAULT_PRECISION,
) -> np.ndarray:
    """Tiled attention using online softmax, matching planned hardware dataflow.

    The outer loop iterates over query-row blocks.  The inner loop streams
    over key/value blocks, maintaining running max and denominator per row
    so softmax never needs the full score matrix in scratchpad at once.
    This mirrors the double-buffered tile scheduling the hardware will use.
    """
    seq_q, d_model = query.shape
    seq_k, _ = key.shape

    q = quantize(query, precision.input_bits).astype(np.int64)
    k = quantize(key, precision.input_bits).astype(np.int64)
    v = quantize(value, precision.input_bits).astype(np.float64)

    output = np.zeros((seq_q, value.shape[1]), dtype=np.float64)

    for q_start, q_end in _tile_ranges(seq_q, tile.tile_m):
        q_block = q[q_start:q_end]
        m_size = q_end - q_start

        row_max = np.full((m_size, 1), -np.inf, dtype=np.float64)
        row_sum = np.zeros((m_size, 1), dtype=np.float64)
        row_out = np.zeros((m_size, value.shape[1]), dtype=np.float64)

        for k_start, k_end in _tile_ranges(seq_k, tile.tile_n):
            k_block = k[k_start:k_end]
            v_block = v[k_start:k_end]

            scores = saturate(
                q_block @ k_block.T,
                precision.accumulator.value,
            ).astype(np.float64)

            if precision.scale_shift > 0:
                scores = np.floor(scores / (1 << precision.scale_shift))

            block_max = np.max(scores, axis=-1, keepdims=True)
            new_max = np.maximum(row_max, block_max)

            # Rescale previous accumulations to the new max.
            correction = np.exp(row_max - new_max)
            row_out = row_out * correction
            row_sum = row_sum * correction

            exp_scores = np.exp(scores - new_max)
            row_out += exp_scores @ v_block
            row_sum += np.sum(exp_scores, axis=-1, keepdims=True)
            row_max = new_max

        output[q_start:q_end] = row_out / row_sum

    return output


# ---------------------------------------------------------------------------
# Scratchpad memory model
# ---------------------------------------------------------------------------

@dataclass
class ScratchpadModel:
    """Software model of the banked scratchpad for tile residency tracking."""
    capacity_bytes: int = 128 * 1024  # 128 KiB baseline
    num_banks: int = 8
    word_bytes: int = 1  # INT8

    def tiles_that_fit(self, tile: TileConfig) -> int:
        tile_bytes = tile.tile_m * tile.tile_n * self.word_bytes
        return self.capacity_bytes // tile_bytes

    def bank_for_address(self, byte_addr: int) -> int:
        bank_size = self.capacity_bytes // self.num_banks
        return byte_addr // bank_size

    def bytes_per_tile(self, tile: TileConfig) -> int:
        return tile.tile_m * tile.tile_n * self.word_bytes

    def double_buffer_feasible(
        self,
        tile: TileConfig,
        tiles_needed: int = 4,
    ) -> bool:
        """Check whether double-buffering the working set is feasible.

        tiles_needed accounts for Q, K, V input tiles plus output tile.
        """
        return self.tiles_that_fit(tile) >= tiles_needed


# ---------------------------------------------------------------------------
# Numeric comparison utilities
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ComparisonResult:
    max_abs_error: float
    mean_abs_error: float
    max_rel_error: float
    cosine_similarity: float
    passed: bool
    detail: str

    def __str__(self) -> str:
        return (
            f"max_abs={self.max_abs_error:.6e}  mean_abs={self.mean_abs_error:.6e}  "
            f"max_rel={self.max_rel_error:.6e}  cosine={self.cosine_similarity:.8f}  "
            f"{'PASS' if self.passed else 'FAIL'}"
        )


def compare(
    reference: np.ndarray,
    candidate: np.ndarray,
    atol: float = 1e-3,
    rtol: float = 1e-2,
    min_cosine: float = 0.999,
) -> ComparisonResult:
    """Compare candidate against reference with configurable thresholds."""
    diff = np.abs(reference - candidate)
    max_abs = float(np.max(diff))
    mean_abs = float(np.mean(diff))

    denom = np.maximum(np.abs(reference), 1e-12)
    max_rel = float(np.max(diff / denom))

    ref_flat = reference.flatten().astype(np.float64)
    cand_flat = candidate.flatten().astype(np.float64)
    norm_r = np.linalg.norm(ref_flat)
    norm_c = np.linalg.norm(cand_flat)
    if norm_r < 1e-12 or norm_c < 1e-12:
        cosine = 1.0 if np.allclose(ref_flat, cand_flat) else 0.0
    else:
        cosine = float(np.dot(ref_flat, cand_flat) / (norm_r * norm_c))

    abs_ok = max_abs <= atol
    rel_ok = max_rel <= rtol
    cos_ok = cosine >= min_cosine
    passed = abs_ok and rel_ok and cos_ok

    failures: list[str] = []
    if not abs_ok:
        failures.append(f"abs {max_abs:.4e} > {atol:.4e}")
    if not rel_ok:
        failures.append(f"rel {max_rel:.4e} > {rtol:.4e}")
    if not cos_ok:
        failures.append(f"cosine {cosine:.6f} < {min_cosine}")
    detail = "; ".join(failures) if failures else "all checks passed"

    return ComparisonResult(
        max_abs_error=max_abs,
        mean_abs_error=mean_abs,
        max_rel_error=max_rel,
        cosine_similarity=cosine,
        passed=passed,
        detail=detail,
    )


# ---------------------------------------------------------------------------
# Workload generation helpers
# ---------------------------------------------------------------------------

def make_workload(
    seq_len: int = 128,
    d_model: int = 64,
    scale: float = 10.0,
    seed: int = 42,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Generate a representative Q, K, V workload in INT8-friendly range."""
    rng = np.random.default_rng(seed)
    q = rng.uniform(-scale, scale, (seq_len, d_model))
    k = rng.uniform(-scale, scale, (seq_len, d_model))
    v = rng.uniform(-scale, scale, (seq_len, d_model))
    return q, k, v
