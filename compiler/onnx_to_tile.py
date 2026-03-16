"""Extract and lower supported ONNX attention fragments into tile descriptors."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .lowering import (
    AttentionLoweringConfig,
    AttentionTileShape,
    DescriptorPlan,
    SlotLayout,
    lower_attention_shape,
)


@dataclass(frozen=True)
class OnnxAttentionSubgraph:
    query_name: str
    key_name: str
    value_name: str
    output_name: str
    shape: AttentionTileShape


@dataclass(frozen=True)
class OnnxLoweringResult:
    subgraph: OnnxAttentionSubgraph
    plan: DescriptorPlan


def _import_onnx():
    try:
        import onnx  # type: ignore
    except ModuleNotFoundError as exc:
        raise RuntimeError("onnx is required to use compiler.onnx_to_tile") from exc
    return onnx


def load_onnx_model(model_or_path: Any):
    onnx = _import_onnx()
    if isinstance(model_or_path, (str, Path)):
        return onnx.load(str(model_or_path))
    return model_or_path


def _extract_shape_map(model) -> tuple[Any, dict[str, tuple[int, ...]]]:
    onnx = _import_onnx()
    inferred = onnx.shape_inference.infer_shapes(model)
    shape_map: dict[str, tuple[int, ...]] = {}

    def capture_value_info(value_info) -> None:
        tensor_type = value_info.type.tensor_type
        if not tensor_type.HasField("shape"):
            return
        dims = []
        for dim in tensor_type.shape.dim:
            if not dim.HasField("dim_value"):
                raise ValueError(f"dynamic dimensions are not supported for {value_info.name}")
            dims.append(int(dim.dim_value))
        shape_map[value_info.name] = tuple(dims)

    for value_info in list(inferred.graph.input) + list(inferred.graph.value_info) + list(inferred.graph.output):
        capture_value_info(value_info)

    return inferred, shape_map


def _build_producer_map(nodes) -> dict[str, Any]:
    producer_map: dict[str, Any] = {}
    for node in nodes:
        for output_name in node.output:
            producer_map[output_name] = node
    return producer_map


def _build_consumer_map(nodes) -> dict[str, list[Any]]:
    consumer_map: dict[str, list[Any]] = {}
    for node in nodes:
        for input_name in node.input:
            consumer_map.setdefault(input_name, []).append(node)
    return consumer_map


def _shape_to_tile(
    query_shape: tuple[int, ...],
    key_shape: tuple[int, ...],
    value_shape: tuple[int, ...],
    output_shape: tuple[int, ...] | None,
) -> AttentionTileShape:
    if len(query_shape) != 2 or len(key_shape) != 2 or len(value_shape) != 2:
        raise ValueError(
            "only rank-2 tensors are supported; "
            f"got query={query_shape}, key={key_shape}, value={value_shape}"
        )

    query_rows, model_dim = query_shape
    key_rows, key_cols = key_shape
    value_rows, value_cols = value_shape

    if model_dim != key_rows:
        raise ValueError(
            f"MatMul mismatch: query shape {query_shape} is incompatible with key shape {key_shape}"
        )
    if key_cols != value_rows:
        raise ValueError(
            f"MatMul mismatch: key shape {key_shape} is incompatible with value shape {value_shape}"
        )
    if output_shape is not None and tuple(output_shape) != (query_rows, value_cols):
        raise ValueError(
            f"final output shape {output_shape} does not match expected {(query_rows, value_cols)}"
        )

    return AttentionTileShape(
        query_rows=int(query_rows),
        model_dim=int(model_dim),
        key_cols=int(key_cols),
        value_cols=int(value_cols),
    )


def extract_attention_subgraph(model_or_path: Any) -> OnnxAttentionSubgraph:
    model = load_onnx_model(model_or_path)
    inferred, shape_map = _extract_shape_map(model)
    nodes = list(inferred.graph.node)
    producer_map = _build_producer_map(nodes)
    consumer_map = _build_consumer_map(nodes)

    for node in nodes:
        if node.op_type != "Softmax" or len(node.input) != 1 or len(node.output) != 1:
            continue

        score_name = node.input[0]
        weight_name = node.output[0]
        matmul_scores = producer_map.get(score_name)
        weight_consumers = consumer_map.get(weight_name, [])

        if matmul_scores is None or matmul_scores.op_type != "MatMul" or len(matmul_scores.input) != 2:
            continue
        if len(weight_consumers) != 1 or weight_consumers[0].op_type != "MatMul":
            continue

        matmul_output = weight_consumers[0]
        if len(matmul_output.input) != 2 or len(matmul_output.output) != 1:
            continue

        query_name, key_name = matmul_scores.input
        if matmul_output.input[0] == weight_name:
            value_name = matmul_output.input[1]
        elif matmul_output.input[1] == weight_name:
            value_name = matmul_output.input[0]
        else:
            continue

        output_name = matmul_output.output[0]
        missing_shapes = [
            tensor_name
            for tensor_name in (query_name, key_name, value_name)
            if tensor_name not in shape_map
        ]
        if missing_shapes:
            raise ValueError(f"shape information missing for tensors: {missing_shapes}")

        output_shape = shape_map.get(output_name)
        shape = _shape_to_tile(
            shape_map[query_name],
            shape_map[key_name],
            shape_map[value_name],
            output_shape,
        )
        return OnnxAttentionSubgraph(
            query_name=query_name,
            key_name=key_name,
            value_name=value_name,
            output_name=output_name,
            shape=shape,
        )

    raise ValueError(
        "no supported MatMul -> Softmax -> MatMul attention pattern was found in the ONNX graph"
    )


def lower_attention_model(
    model_or_path: Any,
    *,
    slots: SlotLayout = SlotLayout(),
    config: AttentionLoweringConfig = AttentionLoweringConfig(),
) -> OnnxLoweringResult:
    subgraph = extract_attention_subgraph(model_or_path)
    plan = lower_attention_shape(subgraph.shape, slots=slots, config=config)
    return OnnxLoweringResult(subgraph=subgraph, plan=plan)


__all__ = [
    "OnnxAttentionSubgraph",
    "OnnxLoweringResult",
    "extract_attention_subgraph",
    "load_onnx_model",
    "lower_attention_model",
]
