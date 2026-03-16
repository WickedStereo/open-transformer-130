"""Lower single-tile attention fragments into the current accelerator ISA."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from sim.rtl_scoreboard import matmul_tile, softmax_fixed
from software.runtime import (
    DEFAULT_QUEUE_BASE,
    DEFAULT_QUEUE_SIZE_LOG2,
    Descriptor,
    Opcode,
    RuntimeProgram,
    SLOT_BYTES,
)


@dataclass(frozen=True)
class SlotLayout:
    query: int = 0
    key: int = 1
    weights: int = 2
    value: int = 3

    def validate(self) -> None:
        slots = [self.query, self.key, self.weights, self.value]
        if len(set(slots)) != len(slots):
            raise ValueError(f"slot assignments must be unique, got {slots}")
        for name, slot_id in (
            ("query", self.query),
            ("key", self.key),
            ("weights", self.weights),
            ("value", self.value),
        ):
            if slot_id < 0 or slot_id > 31:
                raise ValueError(f"{name} slot must be in [0, 31], got {slot_id}")


@dataclass(frozen=True)
class AttentionTileShape:
    query_rows: int
    model_dim: int
    key_cols: int
    value_cols: int

    @property
    def query_bytes(self) -> int:
        return self.query_rows * self.model_dim

    @property
    def key_bytes(self) -> int:
        return self.model_dim * self.key_cols

    @property
    def score_bytes(self) -> int:
        return self.query_rows * self.key_cols

    @property
    def value_bytes(self) -> int:
        return self.key_cols * self.value_cols

    @property
    def output_bytes(self) -> int:
        return self.query_rows * self.value_cols


@dataclass(frozen=True)
class AttentionLoweringConfig:
    score_shift: int = 0
    output_shift: int = 7
    saturate: bool = True
    softmax_approx: bool = True
    queue_base: int = DEFAULT_QUEUE_BASE
    queue_size_log2: int = DEFAULT_QUEUE_SIZE_LOG2
    dma_host_addr: int = 0

    @property
    def score_matmul_flags(self) -> int:
        flags = self.score_shift & 0xF
        if self.saturate:
            flags |= 1 << 6
        return flags

    @property
    def output_matmul_flags(self) -> int:
        flags = self.output_shift & 0xF
        if self.saturate:
            flags |= 1 << 6
        return flags

    @property
    def softmax_flags(self) -> int:
        return 1 << 7 if self.softmax_approx else 0


@dataclass(frozen=True)
class DescriptorPlan:
    shape: AttentionTileShape
    slots: SlotLayout
    config: AttentionLoweringConfig
    descriptors: list[Descriptor]

    def descriptor_words(self) -> list[int]:
        return [int(descriptor) for descriptor in self.descriptors]


@dataclass(frozen=True)
class LoweredAttentionProgram:
    plan: DescriptorPlan
    program: RuntimeProgram
    golden_scores: np.ndarray
    golden_weights: np.ndarray
    golden_output: np.ndarray


def _validate_shape(shape: AttentionTileShape) -> None:
    for name, value in (
        ("query_rows", shape.query_rows),
        ("model_dim", shape.model_dim),
        ("key_cols", shape.key_cols),
        ("value_cols", shape.value_cols),
    ):
        if value <= 0 or value > 255:
            raise ValueError(f"{name} must be in [1, 255], got {value}")

    for name, size in (
        ("query", shape.query_bytes),
        ("key", shape.key_bytes),
        ("scores", shape.score_bytes),
        ("weights", shape.score_bytes),
        ("value", shape.value_bytes),
        ("output", shape.output_bytes),
    ):
        if size > SLOT_BYTES:
            raise ValueError(f"{name} tile exceeds {SLOT_BYTES} bytes, got {size}")


def _as_int8_tile(tile: np.ndarray | list[list[int]], *, name: str) -> np.ndarray:
    array = np.asarray(tile)
    if array.ndim != 2:
        raise ValueError(f"{name} must be rank-2, got shape {array.shape}")
    if np.any(array < -128) or np.any(array > 127):
        raise ValueError(f"{name} contains values outside INT8 range")
    return np.ascontiguousarray(array.astype(np.int8))


def _tile_to_bytes(tile: np.ndarray) -> bytes:
    return tile.astype(np.int8, copy=False).view(np.uint8).tobytes(order="C")


def infer_attention_tile_shape(
    query: np.ndarray | list[list[int]],
    key_t: np.ndarray | list[list[int]],
    value: np.ndarray | list[list[int]],
) -> AttentionTileShape:
    query_tile = _as_int8_tile(query, name="query")
    key_tile = _as_int8_tile(key_t, name="key_t")
    value_tile = _as_int8_tile(value, name="value")

    if query_tile.shape[1] != key_tile.shape[0]:
        raise ValueError(
            f"query columns ({query_tile.shape[1]}) must match key_t rows ({key_tile.shape[0]})"
        )
    if key_tile.shape[1] != value_tile.shape[0]:
        raise ValueError(
            f"key_t columns ({key_tile.shape[1]}) must match value rows ({value_tile.shape[0]})"
        )

    shape = AttentionTileShape(
        query_rows=int(query_tile.shape[0]),
        model_dim=int(query_tile.shape[1]),
        key_cols=int(key_tile.shape[1]),
        value_cols=int(value_tile.shape[1]),
    )
    _validate_shape(shape)
    return shape


def lower_attention_shape(
    shape: AttentionTileShape,
    *,
    slots: SlotLayout = SlotLayout(),
    config: AttentionLoweringConfig = AttentionLoweringConfig(),
) -> DescriptorPlan:
    slots.validate()
    _validate_shape(shape)

    descriptors = [
        Descriptor(Opcode.LOAD_TILE, dst=slots.query, m=shape.query_rows, n=shape.model_dim),
        Descriptor(Opcode.LOAD_TILE, dst=slots.key, m=shape.model_dim, n=shape.key_cols),
        Descriptor(
            Opcode.MATMUL,
            flags=config.score_matmul_flags,
            dst=slots.key,
            src=slots.query,
            m=shape.query_rows,
            n=shape.key_cols,
            k=shape.model_dim,
        ),
        Descriptor(
            Opcode.SOFTMAX,
            flags=config.softmax_flags,
            dst=slots.weights,
            src=slots.key,
            m=shape.query_rows,
            n=shape.key_cols,
        ),
        Descriptor(Opcode.LOAD_TILE, dst=slots.value, m=shape.key_cols, n=shape.value_cols),
        Descriptor(
            Opcode.MATMUL,
            flags=config.output_matmul_flags,
            dst=slots.value,
            src=slots.weights,
            m=shape.query_rows,
            n=shape.value_cols,
            k=shape.key_cols,
        ),
        Descriptor(Opcode.STORE_TILE, src=slots.value, m=shape.query_rows, n=shape.value_cols),
    ]
    return DescriptorPlan(shape=shape, slots=slots, config=config, descriptors=descriptors)


def lower_attention_tile(
    query: np.ndarray | list[list[int]],
    key_t: np.ndarray | list[list[int]],
    value: np.ndarray | list[list[int]],
    *,
    slots: SlotLayout = SlotLayout(),
    config: AttentionLoweringConfig = AttentionLoweringConfig(),
) -> LoweredAttentionProgram:
    query_tile = _as_int8_tile(query, name="query")
    key_tile = _as_int8_tile(key_t, name="key_t")
    value_tile = _as_int8_tile(value, name="value")

    shape = infer_attention_tile_shape(query_tile, key_tile, value_tile)
    plan = lower_attention_shape(shape, slots=slots, config=config)

    golden_scores = matmul_tile(
        query_tile,
        key_tile,
        shift=config.score_shift,
        saturate=config.saturate,
    )
    golden_weights = softmax_fixed(golden_scores)
    golden_output = matmul_tile(
        golden_weights.astype(np.int8),
        value_tile,
        shift=config.output_shift,
        saturate=config.saturate,
    )

    program = RuntimeProgram(
        descriptors=plan.descriptors,
        input_tiles={
            slots.query: _tile_to_bytes(query_tile),
            slots.key: _tile_to_bytes(key_tile),
            slots.value: _tile_to_bytes(value_tile),
        },
        result_slots={"attention_out": (slots.value, shape.output_bytes)},
        queue_base=config.queue_base,
        queue_size_log2=config.queue_size_log2,
        dma_host_addr=config.dma_host_addr,
        default_dims=(shape.query_rows, shape.key_cols, shape.model_dim),
    )
    return LoweredAttentionProgram(
        plan=plan,
        program=program,
        golden_scores=golden_scores,
        golden_weights=golden_weights,
        golden_output=golden_output,
    )


def supported_op_matrix() -> dict[str, str]:
    return {
        "MatMul": "supported for one INT8 tile per operand",
        "Softmax": "supported as row-wise fixed-point approximation",
        "Attention": "supported for single-tile MatMul -> Softmax -> MatMul sequences",
    }


__all__ = [
    "AttentionLoweringConfig",
    "AttentionTileShape",
    "DescriptorPlan",
    "LoweredAttentionProgram",
    "SlotLayout",
    "infer_attention_tile_shape",
    "lower_attention_shape",
    "lower_attention_tile",
    "supported_op_matrix",
]
