"""Tree intermediate representation and structural validation."""

from __future__ import annotations

from collections import deque


OPS = {"LEAF": 0, "NUMERIC_LE": 1, "CATEGORY_EQ": 2}


def validate_nodes(nodes: list[dict], feature_count: int, max_operand: int = (1 << 22) - 1) -> None:
    if not nodes or nodes[0]["node_id"] != 0:
        raise ValueError("Tree must have root node 0")
    ids = {node["node_id"] for node in nodes}
    if ids != set(range(len(nodes))):
        raise ValueError("Node IDs must be contiguous from zero")
    for node in nodes:
        operation = node["operation"]
        if operation not in OPS:
            raise ValueError(f"Invalid operation at node {node['node_id']}")
        if operation == "LEAF":
            if not 0 <= node["class_id"] < 64:
                raise ValueError(f"Invalid leaf class at node {node['node_id']}")
            continue
        if not 0 <= node["feature_id"] < feature_count:
            raise ValueError(f"Invalid feature ID at node {node['node_id']}")
        if not 0 <= node["operand"] <= max_operand:
            raise ValueError(f"Operand does not fit 22 bits at node {node['node_id']}")
        if node["true_child"] not in ids or node["false_child"] not in ids:
            raise ValueError(f"Invalid child pointer at node {node['node_id']}")
    visited: set[int] = set(); queue = deque([0])
    while queue:
        node_id = queue.popleft()
        if node_id in visited:
            continue
        visited.add(node_id)
        node = nodes[node_id]
        if node["operation"] != "LEAF":
            queue.extend([node["true_child"], node["false_child"]])
    if visited != ids:
        raise ValueError(f"Unreachable nodes: {sorted(ids - visited)[:8]}")
