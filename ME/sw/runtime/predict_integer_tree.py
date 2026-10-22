"""Run the exported FPGA Decision Tree using integer arithmetic only.

This runtime never loads sklearn, joblib or HDF5.  It accepts either the node
CSV or the packed 64-bit ROM image and traverses the tree exactly as the RTL
FSM will do.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from ME.sw.export_model.tree_ir import validate_nodes
from ME.sw.runtime.fixed_tree_evaluator import evaluate_one, read_mem


NODE_COLUMNS = ["node_id", "operation", "feature_id", "operand", "true_child", "false_child", "class_id"]


def load_node_csv(path: Path) -> list[dict]:
    frame = pd.read_csv(path)
    missing = [column for column in NODE_COLUMNS if column not in frame.columns]
    if missing:
        raise ValueError(f"Node CSV is missing columns: {missing}")
    nodes = []
    for row in frame.loc[:, NODE_COLUMNS].itertuples(index=False):
        nodes.append({"node_id": int(row.node_id), "operation": str(row.operation),
                      "feature_id": int(row.feature_id), "operand": int(row.operand),
                      "true_child": int(row.true_child), "false_child": int(row.false_child),
                      "class_id": int(row.class_id)})
    return nodes


def load_schema(path: Path) -> pd.DataFrame:
    schema = pd.read_csv(path).sort_values("feature_id")
    if schema.feature_id.tolist() != list(range(len(schema))):
        raise ValueError("feature_id in schema must be contiguous from zero")
    return schema


def validate_encoded_input(frame: pd.DataFrame, schema: pd.DataFrame) -> np.ndarray:
    features = schema.raw_feature.tolist()
    missing = [feature for feature in features if feature not in frame.columns]
    if missing:
        raise ValueError(f"Input CSV is missing encoded features: {missing}")
    values = frame.loc[:, features].apply(pd.to_numeric, errors="raise").to_numpy(dtype=np.int64)
    if (values < 0).any():
        raise ValueError("Encoded hardware features must be unsigned")
    for feature_id, row in schema.reset_index(drop=True).iterrows():
        width = int(row.bit_width)
        column = values[:, feature_id]
        if width == 0:
            if np.any(column != 0):
                raise ValueError(f"Unused feature {row.raw_feature} must be encoded as zero")
            continue
        maximum = (1 << width) - 1
        if np.any(column > maximum):
            raise ValueError(f"Feature {row.raw_feature} exceeds UINT{width}")
        if np.any(column > int(row.saturate_at)):
            raise ValueError(f"Feature {row.raw_feature} exceeds contract saturation {int(row.saturate_at)}")
    return values


def run(nodes: list[dict], values: np.ndarray) -> tuple[np.ndarray, np.ndarray, list[str]]:
    classes = np.empty(len(values), dtype=np.int64)
    leaves = np.empty(len(values), dtype=np.int64)
    paths: list[str] = []
    for index, features in enumerate(values):
        class_id, leaf_id, path = evaluate_one(features, nodes, trace=True)
        classes[index] = class_id; leaves[index] = leaf_id
        paths.append(" ".join(map(str, path)))
    return classes, leaves, paths


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--nodes-csv", type=Path, help="fpga_tree_nodes.csv")
    source.add_argument("--rom-mem", type=Path, help="packed node_rom.mem")
    parser.add_argument("--schema", type=Path, required=True, help="fpga_input_schema.csv")
    parser.add_argument("--input", type=Path, required=True, help="CSV containing encoded integer feature columns")
    parser.add_argument("--output", type=Path, required=True, help="prediction CSV to create")
    args = parser.parse_args()

    schema = load_schema(args.schema)
    nodes = load_node_csv(args.nodes_csv) if args.nodes_csv else read_mem(args.rom_mem)
    validate_nodes(nodes, len(schema))
    input_frame = pd.read_csv(args.input)
    values = validate_encoded_input(input_frame, schema)
    classes, leaves, paths = run(nodes, values)

    output = pd.DataFrame({"row_index": np.arange(len(input_frame)), "predicted_class_id": classes,
                           "predicted_leaf_node": leaves, "node_path": paths})
    if "source_row" in input_frame:
        output.insert(1, "source_row", input_frame.source_row.to_numpy())
    checks = {"rows": len(output), "class_mismatches": None, "leaf_mismatches": None}
    if "expected_class_id" in input_frame:
        mismatch = classes != input_frame.expected_class_id.to_numpy(dtype=np.int64)
        output["class_match"] = ~mismatch
        checks["class_mismatches"] = int(mismatch.sum())
    if "expected_leaf_node" in input_frame:
        mismatch = leaves != input_frame.expected_leaf_node.to_numpy(dtype=np.int64)
        output["leaf_match"] = ~mismatch
        checks["leaf_mismatches"] = int(mismatch.sum())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False)
    print(json.dumps(checks, indent=2))
    if checks["class_mismatches"] not in (None, 0) or checks["leaf_mismatches"] not in (None, 0):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
