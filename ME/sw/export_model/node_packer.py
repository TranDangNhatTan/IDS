"""Pack and unpack the canonical 64-bit decision-tree node word."""

from __future__ import annotations

from .tree_ir import OPS


INVALID_CHILD = 4095


def pack_node(node: dict) -> int:
    op = OPS[node["operation"]]
    feature = 0 if node["operation"] == "LEAF" else int(node["feature_id"])
    operand = 0 if node["operation"] == "LEAF" else int(node["operand"])
    true_child = INVALID_CHILD if node["operation"] == "LEAF" else int(node["true_child"])
    false_child = INVALID_CHILD if node["operation"] == "LEAF" else int(node["false_child"])
    class_id = int(node["class_id"])
    return (op << 62) | (feature << 56) | (operand << 34) | (true_child << 22) | (false_child << 10) | (class_id << 4)


def unpack_node(word: int, node_id: int) -> dict:
    codes = {value: key for key, value in OPS.items()}
    op = (word >> 62) & 0x3
    if op not in codes:
        raise ValueError(f"Invalid operation code at node {node_id}")
    return {"node_id": node_id, "operation": codes[op], "feature_id": (word >> 56) & 0x3F,
            "operand": (word >> 34) & 0x3FFFFF, "true_child": (word >> 22) & 0xFFF,
            "false_child": (word >> 10) & 0xFFF, "class_id": (word >> 4) & 0x3F, "flags": word & 0xF}
