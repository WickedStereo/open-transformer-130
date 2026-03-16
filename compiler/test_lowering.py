"""Unit tests for compiler-side lowering helpers."""

from __future__ import annotations

import numpy as np
import pytest

from compiler.lowering import (
    AttentionLoweringConfig,
    SlotLayout,
    infer_attention_tile_shape,
    lower_attention_tile,
)
from compiler.onnx_to_tile import lower_attention_model
from software.runtime import Descriptor, Opcode


def test_lower_attention_tile_emits_expected_sequence_and_goldens():
    query = np.array([[1, 0], [0, 1]], dtype=np.int8)
    key_t = np.array([[1, 0], [0, 1]], dtype=np.int8)
    value = np.array([[10, 20], [30, 40]], dtype=np.int8)

    lowered = lower_attention_tile(query, key_t, value)

    assert [descriptor.opcode for descriptor in lowered.plan.descriptors] == [
        Opcode.LOAD_TILE,
        Opcode.LOAD_TILE,
        Opcode.MATMUL,
        Opcode.SOFTMAX,
        Opcode.LOAD_TILE,
        Opcode.MATMUL,
        Opcode.STORE_TILE,
    ]
    assert lowered.plan.descriptors[2] == Descriptor(
        Opcode.MATMUL,
        flags=0x40,
        dst=1,
        src=0,
        m=2,
        n=2,
        k=2,
    )
    assert lowered.plan.descriptors[5] == Descriptor(
        Opcode.MATMUL,
        flags=0x47,
        dst=3,
        src=2,
        m=2,
        n=2,
        k=2,
    )
    np.testing.assert_array_equal(
        lowered.golden_weights,
        np.array([[93, 34], [34, 93]], dtype=np.uint8),
    )
    np.testing.assert_array_equal(
        lowered.golden_output,
        np.array([[15, 25], [24, 34]], dtype=np.int8),
    )
    assert lowered.program.result_slots == {"attention_out": (3, 4)}


def test_infer_attention_tile_shape_rejects_mismatched_dims():
    query = np.zeros((2, 3), dtype=np.int8)
    key_t = np.zeros((4, 2), dtype=np.int8)
    value = np.zeros((2, 2), dtype=np.int8)

    with pytest.raises(ValueError, match="query columns"):
        infer_attention_tile_shape(query, key_t, value)


def test_lower_attention_model_finds_supported_onnx_subgraph():
    onnx = pytest.importorskip("onnx")
    helper = onnx.helper
    tensor_proto = onnx.TensorProto

    model = helper.make_model(
        helper.make_graph(
            nodes=[
                helper.make_node("MatMul", ["query", "key_t"], ["scores"]),
                helper.make_node("Softmax", ["scores"], ["weights"], axis=1),
                helper.make_node("MatMul", ["weights", "value"], ["output"]),
            ],
            name="attention_tile",
            inputs=[
                helper.make_tensor_value_info("query", tensor_proto.INT8, [2, 2]),
                helper.make_tensor_value_info("key_t", tensor_proto.INT8, [2, 2]),
                helper.make_tensor_value_info("value", tensor_proto.INT8, [2, 2]),
            ],
            outputs=[
                helper.make_tensor_value_info("output", tensor_proto.INT8, [2, 2]),
            ],
        )
    )

    result = lower_attention_model(
        model,
        slots=SlotLayout(query=4, key=5, weights=6, value=7),
        config=AttentionLoweringConfig(output_shift=5),
    )

    assert result.subgraph.query_name == "query"
    assert result.subgraph.key_name == "key_t"
    assert result.subgraph.value_name == "value"
    assert result.subgraph.shape.query_rows == 2
    assert result.subgraph.shape.model_dim == 2
    assert result.subgraph.shape.key_cols == 2
    assert result.subgraph.shape.value_cols == 2
    assert result.plan.descriptors[5] == Descriptor(
        Opcode.MATMUL,
        flags=0x45,
        dst=7,
        src=6,
        m=2,
        n=2,
        k=2,
    )
