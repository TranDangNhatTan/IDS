"""Train an NSL-KDD Decision Tree on the exact integer feature contract used by FPGA."""

from __future__ import annotations

import argparse
import json
import platform
import shutil
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score, f1_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.tree import DecisionTreeClassifier

from ME.sw.feature_contract.encode import encode_frame, fit_category_codes
from ME.sw.feature_contract.schema import CONFIG_DIR, load_profile
from ME.sw.paths import GROUND_TRUTH_DIR, TREE_DIR
from ME.sw.train_model.train_decision_tree_ground_truth import three_way_split


def metrics(actual: pd.Series, predicted: np.ndarray, labels: list[str]) -> dict[str, float]:
    attack = np.asarray(actual) != "normal"
    attack_pred = np.asarray(predicted) != "normal"
    tn = int(np.count_nonzero(~attack & ~attack_pred)); fp = int(np.count_nonzero(~attack & attack_pred))
    fn = int(np.count_nonzero(attack & ~attack_pred)); tp = int(np.count_nonzero(attack & attack_pred))
    return {
        "accuracy": float(accuracy_score(actual, predicted)),
        "macro_f1": float(f1_score(actual, predicted, labels=labels, average="macro", zero_division=0)),
        "attack_recall": tp / (tp + fn) if tp + fn else 0.0,
        "false_positive_rate": fp / (fp + tn) if fp + tn else 0.0,
        "tn": tn, "fp": fp, "fn": fn, "tp": tp,
    }


def make_pipeline(profile, depth: int | None, min_leaf: int) -> Pipeline:
    preprocessing = ColumnTransformer([
        ("categorical", OneHotEncoder(handle_unknown="ignore", dtype=np.int8), list(profile.categorical_features)),
        ("numeric", "passthrough", list(profile.numeric_features)),
    ])
    return Pipeline([("preprocess", preprocessing), ("model", DecisionTreeClassifier(
        max_depth=depth, min_samples_leaf=min_leaf, class_weight="balanced", random_state=42))])


def cuda_backend_status(requested: str) -> dict[str, str | bool]:
    """Report capability honestly; sklearn tree itself has no CUDA training implementation."""
    if requested not in {"auto", "cpu", "cuml"}:
        raise ValueError("backend must be auto, cpu or cuml")
    if requested == "cpu":
        return {"requested": requested, "used": "sklearn-cpu", "cuda_available": False, "reason": "explicit CPU backend"}
    try:
        import cuml  # noqa: F401
    except ImportError:
        if requested == "cuml":
            raise RuntimeError("--backend cuml requested, but cuML is not installed")
        return {"requested": requested, "used": "sklearn-cpu", "cuda_available": False,
                "reason": "cuML is not installed; sklearn DecisionTreeClassifier is CPU-only"}
    # cuML model serialization/export semantics differ from sklearn. Do not silently
    # substitute it until a parity adapter exists.
    if requested == "cuml":
        raise RuntimeError("--backend cuml is gated until a cuML-to-integer-tree parity adapter is implemented")
    return {"requested": requested, "used": "sklearn-cpu", "cuda_available": True,
            "reason": "cuML detected, but GPU tree export is intentionally gated pending sklearn parity adapter"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["full41", "fpga_flow28"], default="fpga_flow28")
    parser.add_argument("--ground-truth", type=Path, default=GROUND_TRUTH_DIR / "ground_truth_nsl_kdd.csv")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--backend", default="auto", choices=["auto", "cpu", "cuml"])
    args = parser.parse_args()
    profile = load_profile(args.profile)
    config = json.loads((CONFIG_DIR / f"training_{args.profile.replace('fpga_flow28', 'fpga_flow')}.json").read_text(encoding="utf-8"))
    output = (args.output_dir or TREE_DIR / f"dt_{args.profile}_fixed").resolve()
    backend = cuda_backend_status(args.backend)
    output.mkdir(parents=True, exist_ok=False)

    data = pd.read_csv(args.ground_truth)
    if data.isna().any().any() or "label" not in data:
        raise ValueError("Ground truth must contain labels and no missing values")
    categories = fit_category_codes(data, profile)
    encoded = encode_frame(data, profile, categories)
    y = data.label.astype(str)
    labels = sorted(y.unique())
    train_ids, validation_ids, test_ids = three_way_split(y, seed=int(config["random_seed"]))
    candidates = [(depth, leaf) for depth in config["candidate_max_depth"] for leaf in config["candidate_min_samples_leaf"]]
    history: list[dict] = []
    for depth, leaf in candidates:
        model = make_pipeline(profile, depth, leaf).fit(encoded.iloc[train_ids], y.iloc[train_ids])
        validation = metrics(y.iloc[validation_ids], model.predict(encoded.iloc[validation_ids]), sorted(y.iloc[validation_ids].unique()))
        tree = model.named_steps["model"]
        history.append({"max_depth": "unlimited" if depth is None else depth, "min_samples_leaf": leaf,
                        "node_count": int(tree.tree_.node_count), "leaf_count": int(tree.get_n_leaves()), **{f"validation_{k}": v for k, v in validation.items()}})
    pd.DataFrame(history).to_csv(output / "selection_metrics.csv", index=False)
    best_f1 = max(row["validation_macro_f1"] for row in history)
    eligible = [row for row in history if row["validation_macro_f1"] >= best_f1 - float(config["macro_f1_tolerance"])]
    selected = min(eligible, key=lambda row: (row["node_count"], -row["validation_attack_recall"], row["validation_false_positive_rate"]))
    depth = None if selected["max_depth"] == "unlimited" else int(selected["max_depth"])
    development_ids = np.sort(np.concatenate([train_ids, validation_ids]))
    final = make_pipeline(profile, depth, int(selected["min_samples_leaf"])).fit(encoded.iloc[development_ids], y.iloc[development_ids])
    prediction = final.predict(encoded.iloc[test_ids])
    test = metrics(y.iloc[test_ids], prediction, labels)
    tree = final.named_steps["model"]
    joblib.dump(final, output / "pipeline.joblib")
    (output / "category_codes.json").write_text(json.dumps(categories, indent=2, sort_keys=True), encoding="utf-8")
    profile_file = {"fpga_flow28": "fpga_flow"}.get(args.profile, args.profile)
    shutil.copy2(CONFIG_DIR / f"feature_profile_{profile_file}.json", output / "feature_profile.json")
    shutil.copy2(CONFIG_DIR / "class_map.json", output / "class_map.json")
    np.savez_compressed(output / "encoded_splits.npz", train=train_ids, validation=validation_ids, test=test_ids)
    metadata = {"model": "DecisionTreeClassifier", "profile": args.profile, "profile_sha256": profile.sha256,
                "backend": backend, "seed": int(config["random_seed"]), "selected": selected,
                "actual_depth": int(tree.get_depth()), "node_count": int(tree.tree_.node_count), "leaf_count": int(tree.get_n_leaves()),
                "test_metrics": test, "sklearn": sklearn.__version__, "python": platform.python_version(),
                "ground_truth_rows": len(data), "feature_count": len(profile.features), "class_count": len(labels)}
    (output / "run_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    pd.DataFrame({"row": test_ids, "actual": y.iloc[test_ids].to_numpy(), "predicted": prediction}).to_csv(output / "test_predictions.csv", index=False)
    # Produce the framework-neutral integer model requested by the FPGA flow.
    from ME.sw.export_model.create_h5_model import create
    create(output)
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
