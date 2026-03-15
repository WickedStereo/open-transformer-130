"""Analytical performance model for the attention accelerator.

Evaluates tile-size options against scratchpad capacity and memory traffic,
estimates MAC utilization and latency sensitivity to DMA overlap assumptions,
and produces sweep data for architecture decision-making.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from sim.reference_attention import (
    ScratchpadModel,
    TileConfig,
)


# ---------------------------------------------------------------------------
# Hardware configuration
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class HardwareConfig:
    clock_mhz: float = 150.0
    mac_lanes: int = 16
    mac_pipe_stages: int = 3
    operand_bytes: int = 1  # INT8
    accum_bytes: int = 4    # INT32
    mem_bandwidth_gbps: float = 1.6  # host-facing bandwidth
    scratchpad: ScratchpadModel = field(default_factory=ScratchpadModel)
    dma_efficiency: float = 0.85
    scheduler_overhead_cycles: int = 8

    @property
    def mac_ops_per_cycle(self) -> int:
        return self.mac_lanes

    @property
    def peak_gops(self) -> float:
        return self.mac_ops_per_cycle * self.clock_mhz / 1000.0


DEFAULT_HW = HardwareConfig()


# ---------------------------------------------------------------------------
# Workload description
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class AttentionWorkload:
    seq_len: int = 128
    d_model: int = 64
    num_heads: int = 1

    @property
    def d_head(self) -> int:
        return self.d_model // self.num_heads

    @property
    def total_score_ops(self) -> int:
        """MACs for Q @ K^T: seq_len * seq_len * d_head per head."""
        return self.num_heads * self.seq_len * self.seq_len * self.d_head

    @property
    def total_value_ops(self) -> int:
        """MACs for weights @ V: seq_len * d_head * seq_len per head."""
        return self.num_heads * self.seq_len * self.d_head * self.seq_len

    @property
    def total_mac_ops(self) -> int:
        return self.total_score_ops + self.total_value_ops


# ---------------------------------------------------------------------------
# Performance estimates
# ---------------------------------------------------------------------------

@dataclass
class PerformanceEstimate:
    tile: TileConfig
    hw: HardwareConfig
    workload: AttentionWorkload

    compute_cycles: int = 0
    dma_load_cycles: int = 0
    dma_store_cycles: int = 0
    scheduler_cycles: int = 0
    total_cycles: int = 0

    tiles_q: int = 0
    tiles_k: int = 0
    total_tile_invocations: int = 0
    tiles_fit_in_scratchpad: int = 0
    double_buffer_ok: bool = False

    mac_utilization: float = 0.0
    effective_gops: float = 0.0
    latency_us: float = 0.0
    dma_bytes_loaded: int = 0
    dma_bytes_stored: int = 0
    dma_bandwidth_demand_gbps: float = 0.0
    bottleneck: str = ""

    def summary_dict(self) -> dict:
        return {
            "tile_m": self.tile.tile_m,
            "tile_n": self.tile.tile_n,
            "compute_cycles": self.compute_cycles,
            "dma_load_cycles": self.dma_load_cycles,
            "dma_store_cycles": self.dma_store_cycles,
            "scheduler_cycles": self.scheduler_cycles,
            "total_cycles": self.total_cycles,
            "mac_utilization": round(self.mac_utilization, 4),
            "effective_gops": round(self.effective_gops, 4),
            "latency_us": round(self.latency_us, 2),
            "tiles_fit": self.tiles_fit_in_scratchpad,
            "double_buffer_ok": self.double_buffer_ok,
            "dma_bytes_total": self.dma_bytes_loaded + self.dma_bytes_stored,
            "dma_bw_gbps": round(self.dma_bandwidth_demand_gbps, 3),
            "bottleneck": self.bottleneck,
        }


def estimate(
    tile: TileConfig,
    hw: HardwareConfig = DEFAULT_HW,
    workload: AttentionWorkload = AttentionWorkload(),
    dma_compute_overlap: float = 0.5,
) -> PerformanceEstimate:
    """First-order performance estimate for one attention layer."""
    est = PerformanceEstimate(tile=tile, hw=hw, workload=workload)

    s = workload.seq_len
    d = workload.d_head
    tm, tn = tile.tile_m, tile.tile_n

    est.tiles_q = int(np.ceil(s / tm))
    est.tiles_k = int(np.ceil(s / tn))

    # Score phase: each (q_block, k_block) pair does tm * tn * d MACs.
    score_tile_ops = tm * tn * d
    # Value phase: each (q_block, v_block) pair does tm * d * tn MACs.
    value_tile_ops = tm * d * tn

    score_invocations = est.tiles_q * est.tiles_k
    value_invocations = est.tiles_q * est.tiles_k
    est.total_tile_invocations = score_invocations + value_invocations

    total_ops = score_invocations * score_tile_ops + value_invocations * value_tile_ops
    est.compute_cycles = int(np.ceil(total_ops / hw.mac_ops_per_cycle))
    est.compute_cycles += hw.mac_pipe_stages * est.total_tile_invocations

    # DMA traffic: load Q, K, V tiles; store output tiles.
    q_load_bytes = est.tiles_q * tm * d * hw.operand_bytes
    k_load_bytes = est.tiles_q * est.tiles_k * tn * d * hw.operand_bytes
    v_load_bytes = est.tiles_q * est.tiles_k * tn * d * hw.operand_bytes
    est.dma_bytes_loaded = q_load_bytes + k_load_bytes + v_load_bytes

    est.dma_bytes_stored = est.tiles_q * tm * d * hw.accum_bytes

    bytes_per_cycle = (hw.mem_bandwidth_gbps * 1e9) / (hw.clock_mhz * 1e6)
    effective_bpc = bytes_per_cycle * hw.dma_efficiency
    est.dma_load_cycles = int(np.ceil(est.dma_bytes_loaded / effective_bpc))
    est.dma_store_cycles = int(np.ceil(est.dma_bytes_stored / effective_bpc))
    total_dma_cycles = est.dma_load_cycles + est.dma_store_cycles

    est.scheduler_cycles = hw.scheduler_overhead_cycles * est.total_tile_invocations

    # Overlap model: fraction of DMA hidden behind compute.
    visible_dma = int(total_dma_cycles * (1.0 - dma_compute_overlap))
    est.total_cycles = est.compute_cycles + visible_dma + est.scheduler_cycles

    est.mac_utilization = total_ops / (est.total_cycles * hw.mac_ops_per_cycle)

    est.effective_gops = total_ops / (est.total_cycles / (hw.clock_mhz * 1e6)) / 1e9
    est.latency_us = est.total_cycles / hw.clock_mhz

    total_time_s = est.total_cycles / (hw.clock_mhz * 1e6)
    total_bytes = est.dma_bytes_loaded + est.dma_bytes_stored
    est.dma_bandwidth_demand_gbps = total_bytes / total_time_s / 1e9

    est.tiles_fit_in_scratchpad = hw.scratchpad.tiles_that_fit(tile)
    est.double_buffer_ok = hw.scratchpad.double_buffer_feasible(tile)

    if est.compute_cycles >= total_dma_cycles:
        est.bottleneck = "compute"
    else:
        est.bottleneck = "memory"

    return est


# ---------------------------------------------------------------------------
# Sweep helpers
# ---------------------------------------------------------------------------

def tile_sweep(
    tile_sizes: list[int] | None = None,
    hw: HardwareConfig = DEFAULT_HW,
    workload: AttentionWorkload = AttentionWorkload(),
    dma_compute_overlap: float = 0.5,
) -> list[PerformanceEstimate]:
    if tile_sizes is None:
        tile_sizes = [8, 16, 32, 64, 128]
    results = []
    for ts in tile_sizes:
        t = TileConfig(tile_m=ts, tile_n=ts)
        est = estimate(t, hw, workload, dma_compute_overlap)
        results.append(est)
    return results


DEFAULT_TILE = TileConfig()


def overlap_sensitivity(
    tile: TileConfig = DEFAULT_TILE,
    hw: HardwareConfig = DEFAULT_HW,
    workload: AttentionWorkload = AttentionWorkload(),
    overlaps: list[float] | None = None,
) -> list[PerformanceEstimate]:
    if overlaps is None:
        overlaps = [0.0, 0.25, 0.5, 0.75, 1.0]
    return [estimate(tile, hw, workload, ov) for ov in overlaps]


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def format_sweep_table(results: list[PerformanceEstimate]) -> str:
    header = (
        f"{'Tile':>6} {'Compute':>10} {'DMA':>10} {'Sched':>8} "
        f"{'Total':>10} {'Util':>7} {'GOPS':>7} {'us':>8} "
        f"{'Fit':>4} {'2xBuf':>5} {'Bottleneck':>10}"
    )
    lines = [header, "-" * len(header)]
    for r in results:
        lines.append(
            f"{r.tile.tile_m:>3}x{r.tile.tile_n:<3}"
            f"{r.compute_cycles:>10}"
            f"{r.dma_load_cycles + r.dma_store_cycles:>10}"
            f"{r.scheduler_cycles:>8}"
            f"{r.total_cycles:>10}"
            f"{r.mac_utilization:>7.1%}"
            f"{r.effective_gops:>7.2f}"
            f"{r.latency_us:>8.1f}"
            f"{r.tiles_fit_in_scratchpad:>4}"
            f"{'yes' if r.double_buffer_ok else 'NO':>5}"
            f"{r.bottleneck:>10}"
        )
    return "\n".join(lines)


if __name__ == "__main__":
    print("=== Tile-size sweep (seq=128, d=64, 150 MHz, 16 MACs) ===\n")
    results = tile_sweep()
    print(format_sweep_table(results))

    print("\n=== DMA overlap sensitivity (64x64 tile) ===\n")
    sens = overlap_sensitivity()
    header = f"{'Overlap':>8} {'Total cyc':>10} {'Util':>7} {'GOPS':>7} {'us':>8}"
    print(header)
    print("-" * len(header))
    for i, ov in enumerate([0.0, 0.25, 0.5, 0.75, 1.0]):
        r = sens[i]
        print(
            f"{ov:>8.0%}"
            f"{r.total_cycles:>10}"
            f"{r.mac_utilization:>7.1%}"
            f"{r.effective_gops:>7.2f}"
            f"{r.latency_us:>8.1f}"
        )

    print("\n=== Larger workload: seq=512, d=64 ===\n")
    big = AttentionWorkload(seq_len=512, d_model=64)
    results_big = tile_sweep(workload=big)
    print(format_sweep_table(results_big))
