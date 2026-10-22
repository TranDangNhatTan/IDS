"""Integer-only HDF5 container for a trained decision tree.

The HDF5 file is the framework-neutral deployment model.  It contains no
pickle/joblib objects and no floating-point thresholds.
"""

from __future__ import annotations

import json
from pathlib import Path

import h5py
import numpy as np

from .tree_ir import OPS, validate_nodes


FORMAT_NAME = "fpga_integer_tree"
FORMAT_VERSION = 1


def save_h5(path: Path, nodes: list[dict], *, profile_name: str, profile_sha256: str,
            feature_names: tuple[str, ...], category_codes: dict, class_ids: dict[str, int]) -> None:
    validate_nodes(nodes, len(feature_names))
    path = Path(path)
    with h5py.File(path, "w") as handle:
        handle.attrs["format"] = FORMAT_NAME
        handle.attrs["format_version"] = FORMAT_VERSION
        handle.attrs["profile"] = profile_name
        handle.attrs["profile_sha256"] = profile_sha256
        handle.attrs["root_node"] = 0
        handle.attrs["node_count"] = len(nodes)
        handle.attrs["feature_names_json"] = json.dumps(feature_names)
        handle.attrs["category_codes_json"] = json.dumps(category_codes, sort_keys=True)
        handle.attrs["class_map_json"] = json.dumps(class_ids, sort_keys=True)
        group = handle.create_group("nodes")
        group.create_dataset("operation", data=np.asarray([OPS[node["operation"]] for node in nodes], dtype=np.uint8))
        group.create_dataset("feature_id", data=np.asarray([node["feature_id"] for node in nodes], dtype=np.uint8))
        group.create_dataset("operand", data=np.asarray([node["operand"] for node in nodes], dtype=np.uint32))
        group.create_dataset("true_child", data=np.asarray([node["true_child"] for node in nodes], dtype=np.uint16))
        group.create_dataset("false_child", data=np.asarray([node["false_child"] for node in nodes], dtype=np.uint16))
        group.create_dataset("class_id", data=np.asarray([node["class_id"] for node in nodes], dtype=np.uint8))


def load_h5(path: Path) -> tuple[list[dict], dict]:
    reverse_ops = {value: key for key, value in OPS.items()}
    with h5py.File(path, "r") as handle:
        if handle.attrs.get("format") != FORMAT_NAME or int(handle.attrs.get("format_version", -1)) != FORMAT_VERSION:
            raise ValueError(f"Unsupported HDF5 tree format: {path}")
        arrays = {name: handle["nodes"][name][:] for name in ("operation", "feature_id", "operand", "true_child", "false_child", "class_id")}
        count = len(arrays["operation"])
        if any(len(values) != count for values in arrays.values()) or count != int(handle.attrs["node_count"]):
            raise ValueError("Inconsistent HDF5 node-array lengths")
        nodes = [{"node_id": index, "operation": reverse_ops[int(arrays["operation"][index])],
                  "feature_id": int(arrays["feature_id"][index]), "operand": int(arrays["operand"][index]),
                  "true_child": int(arrays["true_child"][index]), "false_child": int(arrays["false_child"][index]),
                  "class_id": int(arrays["class_id"][index])} for index in range(count)]
        metadata = {"profile": str(handle.attrs["profile"]), "profile_sha256": str(handle.attrs["profile_sha256"]),
                    "feature_names": tuple(json.loads(handle.attrs["feature_names_json"])),
                    "category_codes": json.loads(handle.attrs["category_codes_json"]),
                    "class_map": json.loads(handle.attrs["class_map_json"])}
    validate_nodes(nodes, len(metadata["feature_names"]))
    return nodes, metadata
