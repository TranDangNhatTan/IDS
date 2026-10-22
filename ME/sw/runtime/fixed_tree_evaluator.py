"""Framework-free integer Decision Tree evaluator for CSV/ROM artifacts."""

from __future__ import annotations

import numpy as np

from ME.sw.export_model.node_packer import unpack_node


def evaluate_one(features: np.ndarray, nodes: list[dict], *, trace: bool = False) -> tuple[int, int, list[int]]:
    node_id = 0; path: list[int] = []
    for _ in range(len(nodes) + 1):
        node = nodes[node_id]; path.append(node_id)
        if node["operation"] == "LEAF":
            return int(node["class_id"]), node_id, path if trace else []
        value = int(features[int(node["feature_id"])])
        if node["operation"] == "NUMERIC_LE":
            condition = value <= int(node["operand"])
        elif node["operation"] == "CATEGORY_EQ":
            condition = value == int(node["operand"])
        else:
            raise ValueError(f"Unsupported node operation {node['operation']}")
        node_id = int(node["true_child"] if condition else node["false_child"])
    raise ValueError("Tree traversal exceeded node count; cycle suspected")


def evaluate_many(features: np.ndarray, nodes: list[dict]) -> np.ndarray:
    return np.asarray([evaluate_one(row, nodes)[0] for row in features], dtype=np.int64)


def read_mem(path) -> list[dict]:
    words = [int(line.strip(), 16) for line in open(path, encoding="ascii") if line.strip()]
    return [unpack_node(word, index) for index, word in enumerate(words)]
