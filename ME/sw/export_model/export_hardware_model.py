"""Export a hardware-aware sklearn Decision Tree into CSV, ROM and golden vectors."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from ME.sw.export_model.node_packer import pack_node, unpack_node
from ME.sw.export_model.h5_tree import load_h5
from ME.sw.export_model.tree_ir import validate_nodes
from ME.sw.feature_contract.encode import encode_frame, feature_bit_width
from ME.sw.feature_contract.schema import load_profile
from ME.sw.paths import GROUND_TRUTH_DIR, HW_EXPORT_DIR
from ME.sw.runtime.fixed_tree_evaluator import evaluate_many, evaluate_one, read_mem


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_nodes(model, profile, class_ids: dict[str, int]) -> tuple[list[dict], dict[str, int]]:
    preprocessing = model.named_steps["preprocess"]; tree = model.named_steps["model"]
    names = list(preprocessing.get_feature_names_out())
    name_to_index = {name: index for index, name in enumerate(names)}
    category_indices: dict[int, tuple[str, int]] = {}
    encoder = preprocessing.named_transformers_["categorical"]
    for feature, values in zip(profile.categorical_features, encoder.categories_):
        for code in values:
            category_indices[name_to_index[f"categorical__{feature}_{int(code)}"]] = (feature, int(code))
    thresholds: dict[str, list[int]] = {feature: [] for feature in profile.numeric_features}
    nodes: list[dict] = []
    for node_id in range(tree.tree_.node_count):
        encoded = int(tree.tree_.feature[node_id])
        predicted = str(tree.classes_[tree.tree_.value[node_id, 0].argmax()])
        if encoded < 0:
            nodes.append({"node_id": node_id, "operation": "LEAF", "feature_id": 0, "operand": 0,
                          "true_child": 4095, "false_child": 4095, "class_id": class_ids[predicted]})
        elif encoded in category_indices:
            feature, code = category_indices[encoded]
            nodes.append({"node_id": node_id, "operation": "CATEGORY_EQ", "feature_id": profile.features.index(feature),
                          "operand": code, "true_child": int(tree.tree_.children_right[node_id]),
                          "false_child": int(tree.tree_.children_left[node_id]), "class_id": class_ids[predicted]})
        else:
            feature = names[encoded].removeprefix("numeric__")
            operand = math.floor(float(tree.tree_.threshold[node_id]))
            thresholds[feature].append(operand)
            nodes.append({"node_id": node_id, "operation": "NUMERIC_LE", "feature_id": profile.features.index(feature),
                          "operand": operand, "true_child": int(tree.tree_.children_left[node_id]),
                          "false_child": int(tree.tree_.children_right[node_id]), "class_id": class_ids[predicted]})
    return nodes, {feature: (max(values) + 1 if values else 0) for feature, values in thresholds.items()}


def write_input_schema(path: Path, profile, categories: dict, saturations: dict[str, int]) -> None:
    rows = []
    for index, feature in enumerate(profile.features):
        if feature in profile.categorical_features:
            maximum = max(categories[feature].values())
            rows.append({"feature_id": index, "raw_feature": feature, "representation": "CATEGORY_CODE", "bit_width": feature_bit_width(maximum), "scale": 1, "saturate_at": maximum})
        elif feature in profile.rate_features:
            rows.append({"feature_id": index, "raw_feature": feature, "representation": "UINT_Q0_16", "bit_width": 16, "scale": profile.rate_scale, "saturate_at": profile.rate_scale})
        else:
            cap = saturations[feature]
            rows.append({"feature_id": index, "raw_feature": feature, "representation": "UINT_SAT" if cap else "UNUSED", "bit_width": feature_bit_width(cap) if cap else 0, "scale": profile.integer_divisors.get(feature, 1), "saturate_at": cap})
    pd.DataFrame(rows).to_csv(path, index=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--ground-truth", type=Path, default=GROUND_TRUTH_DIR / "ground_truth_nsl_kdd.csv")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    model_dir = args.model_dir.resolve(); run = json.loads((model_dir / "run_metadata.json").read_text(encoding="utf-8"))
    profile = load_profile(run["profile"]); output = (args.output_dir or HW_EXPORT_DIR / model_dir.name).resolve()
    output.mkdir(parents=True, exist_ok=False)
    categories = json.loads((model_dir / "category_codes.json").read_text(encoding="utf-8"))
    class_ids = json.loads((model_dir / "class_map.json").read_text(encoding="utf-8"))
    h5_path = model_dir / "model_integer.h5"
    nodes, h5_metadata = load_h5(h5_path)
    if (h5_metadata["profile"] != profile.name or h5_metadata["profile_sha256"] != profile.sha256
            or h5_metadata["feature_names"] != profile.features
            or h5_metadata["category_codes"] != categories or h5_metadata["class_map"] != class_ids):
        raise ValueError("HDF5 deployment model metadata does not match the run contract")
    saturation = {feature: 0 for feature in profile.numeric_features}
    for node in nodes:
        if node["operation"] == "NUMERIC_LE":
            feature = profile.features[node["feature_id"]]
            saturation[feature] = max(saturation[feature], int(node["operand"]) + 1)
    validate_nodes(nodes, len(profile.features))
    fields = ["node_id", "operation", "feature_id", "operand", "true_child", "false_child", "class_id"]
    pd.DataFrame(nodes, columns=fields).to_csv(output / "fpga_tree_nodes.csv", index=False)
    words = [pack_node(node) for node in nodes]
    with (output / "node_rom.mem").open("w", encoding="ascii", newline="\n") as handle:
        handle.writelines(f"{word:016X}\n" for word in words)
    (output / "node_rom.hex").write_text((output / "node_rom.mem").read_text(encoding="ascii"), encoding="ascii")
    (output / "node_rom.coe").write_text("memory_initialization_radix=16;\nmemory_initialization_vector=\n" + ",\n".join(f"{word:016X}" for word in words) + ";\n", encoding="ascii")
    (output / "node_rom.mif").write_text("WIDTH=64;\nDEPTH=%d;\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n" % len(words) + "\n".join(f"{i} : {word:016X};" for i, word in enumerate(words)) + "\nEND;\n", encoding="ascii")
    pd.DataFrame([{**node, "word_hex": f"{word:016X}"} for node, word in zip(nodes, words)]).to_csv(output / "node_words.csv", index=False)
    write_input_schema(output / "fpga_input_schema.csv", profile, categories, saturation)
    pd.DataFrame([{"raw_feature": feature, "category": name, "code": code} for feature, mapping in categories.items() for name, code in mapping.items()]).to_csv(output / "fpga_category_codes.csv", index=False)
    pd.DataFrame(sorted(class_ids.items(), key=lambda item: item[1]), columns=["class_name", "class_id"]).to_csv(output / "class_map.csv", index=False)

    data = pd.read_csv(args.ground_truth)
    encoded_frame = encode_frame(data, profile, categories)
    encoded = encoded_frame.to_numpy(dtype=np.int64)
    hardware_encoded = encoded.copy()
    # Match the actual feature-register contract. Values above the largest tree
    # threshold are decision-equivalent and must be saturated so every golden
    # value fits the exported bit width.
    for feature in profile.numeric_features:
        feature_id = profile.features.index(feature)
        cap = profile.rate_scale if feature in profile.rate_features else saturation[feature]
        hardware_encoded[:, feature_id] = np.minimum(hardware_encoded[:, feature_id], cap)
    split = np.load(model_dir / "encoded_splits.npz")["test"]
    # The joblib model is used only as an offline oracle for release parity. All
    # exported inference paths below read the integer HDF5/CSV/ROM representation.
    model = joblib.load(model_dir / "pipeline.joblib")
    expected_names = model.predict(pd.DataFrame(encoded, columns=profile.features))
    expected = np.asarray([class_ids[name] for name in expected_names], dtype=np.int64)
    csv_pred = evaluate_many(hardware_encoded, nodes); rom_nodes = read_mem(output / "node_rom.mem"); rom_pred = evaluate_many(hardware_encoded, rom_nodes)
    if not (np.array_equal(expected, csv_pred) and np.array_equal(expected, rom_pred)):
        raise AssertionError("Model, CSV evaluator and ROM evaluator differ")
    golden = []
    paths = []
    for vector_id, source_row in enumerate(split):
        class_id, leaf, path = evaluate_one(hardware_encoded[source_row], nodes, trace=True)
        golden.append([vector_id, int(source_row), *hardware_encoded[source_row].tolist(), class_id, leaf])
        paths.append({"vector_id": vector_id, "source_row": int(source_row), "path": " ".join(map(str, path))})
    pd.DataFrame(golden, columns=["vector_id", "source_row", *profile.features, "expected_class_id", "expected_leaf_node"]).to_csv(output / "golden_vectors.csv", index=False)
    pd.DataFrame(paths).to_csv(output / "golden_paths.csv", index=False)
    manifest = {"profile": profile.name, "profile_sha256": profile.sha256, "node_count": len(nodes), "word_bits": 64,
                "golden_vector_count": len(golden), "offline_model_sha256": sha256(model_dir / "pipeline.joblib"),
                "integer_h5_sha256": sha256(h5_path),
                "files": {path.name: sha256(path) for path in output.iterdir() if path.is_file()},
                "parity": {"model_equals_csv": True, "model_equals_rom": True, "rows_checked": len(encoded)}}
    (output / "model_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (output / "parity_report.json").write_text(json.dumps(manifest["parity"], indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
