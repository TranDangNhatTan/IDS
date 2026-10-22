"""Train a compact multiclass Decision Tree on the merged project ground truth."""

import argparse
import json
import math
import platform
import sys
import time
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.tree import DecisionTreeClassifier

from ME.sw.analysis.investigate_model_failures import FAMILIES
from ME.sw.paths import GROUND_TRUTH_DIR, GROUND_TRUTH_MODEL_DIR
from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, NUMERIC, SEED, metrics, plt, sha256, write_json


def three_way_split(y, seed=SEED):
    """Class-aware 70/15/15 split, preserving train/test for two-sample classes."""
    rng = np.random.default_rng(seed)
    train_ids, validation_ids, test_ids = [], [], []
    for label in sorted(y.unique()):
        ids = np.flatnonzero(y.to_numpy() == label)
        rng.shuffle(ids)
        count = len(ids)
        if count == 1:
            train_count, validation_count = 1, 0
        elif count == 2:
            train_count, validation_count = 1, 0
        else:
            validation_count = max(1, int(round(count * 0.15)))
            test_count = max(1, int(round(count * 0.15)))
            if validation_count + test_count >= count:
                validation_count, test_count = 1, 1
            train_count = count - validation_count - test_count
        test_count = count - train_count - validation_count
        train_ids.extend(ids[:train_count])
        validation_ids.extend(ids[train_count:train_count + validation_count])
        test_ids.extend(ids[train_count + validation_count:])
    return tuple(np.sort(part) for part in (train_ids, validation_ids, test_ids))


def build_pipeline(depth, min_leaf):
    preprocessing = ColumnTransformer([
        ("categorical", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL),
        ("numeric", "passthrough", NUMERIC),
    ])
    tree = DecisionTreeClassifier(max_depth=depth, min_samples_leaf=min_leaf, class_weight="balanced", random_state=SEED)
    return Pipeline([("preprocess", preprocessing), ("model", tree)])


def evaluate(y_true, predicted, labels):
    binary = metrics(np.asarray(y_true) != "normal", np.asarray(predicted) != "normal")
    return {"accuracy": float(accuracy_score(y_true, predicted)),
            "macro_f1": float(f1_score(y_true, predicted, labels=labels, average="macro", zero_division=0)),
            "weighted_f1": float(f1_score(y_true, predicted, labels=labels, average="weighted", zero_division=0)),
            **{f"binary_{key}": value for key, value in binary.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ground-truth", type=Path, default=GROUND_TRUTH_DIR / "ground_truth_nsl_kdd.csv")
    parser.add_argument("--output-dir", type=Path, default=GROUND_TRUTH_MODEL_DIR)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)

    def log(message):
        print(message, flush=True)
        with (output / "training.log").open("a", encoding="utf-8") as handle:
            handle.write(message + "\n")

    data = pd.read_csv(args.ground_truth)
    if list(data.columns) != FEATURES + ["label"] or data.isna().any().any():
        raise ValueError("Ground truth must contain exactly 41 ordered features plus label, without missing values")
    if data.duplicated(FEATURES).any():
        raise ValueError("Ground truth contains duplicate feature vectors")
    X, y = data[FEATURES], data.label.astype(str)
    labels = sorted(y.unique())
    if set(labels) != set(FAMILIES):
        raise ValueError("Ground truth labels do not match the documented 40 NSL-KDD labels")
    train_ids, validation_ids, test_ids = three_way_split(y)
    all_ids = set(train_ids) | set(validation_ids) | set(test_ids)
    assert len(all_ids) == len(data) and not (set(train_ids) & set(validation_ids) or set(train_ids) & set(test_ids) or set(validation_ids) & set(test_ids))
    split = pd.DataFrame({"source_row_zero_based": range(len(data)), "split": "train", "actual_type": y})
    split.loc[validation_ids, "split"] = "validation"
    split.loc[test_ids, "split"] = "test"
    split.to_csv(output / "split_assignments.csv", index=False)
    supports = pd.DataFrame({"ground_truth": y.value_counts(), "train": y.iloc[list(train_ids)].value_counts(),
                             "validation": y.iloc[list(validation_ids)].value_counts(), "test": y.iloc[list(test_ids)].value_counts()}).fillna(0).astype(int).sort_index()
    supports.to_csv(output / "class_support.csv", index_label="attack_type")
    validation_labels = sorted(y.iloc[list(validation_ids)].unique())
    log(f"features=41; rows={len(data)}; classes={len(labels)}; split train={len(train_ids)}, validation={len(validation_ids)}, test={len(test_ids)}")
    absent_validation = sorted(set(labels)-set(validation_labels))
    log(f"Classes absent from validation because of two-sample support: {absent_validation}")

    candidates = [(12, 1), (16, 1), (20, 1), (24, 1), (None, 1), (16, 2), (20, 2), (24, 2), (None, 2), (20, 4), (24, 4), (None, 4)]
    history = []
    X_train, y_train = X.iloc[list(train_ids)], y.iloc[list(train_ids)]
    X_validation, y_validation = X.iloc[list(validation_ids)], y.iloc[list(validation_ids)]
    for depth, min_leaf in candidates:
        pipeline = build_pipeline(depth, min_leaf)
        start = time.perf_counter()
        pipeline.fit(X_train, y_train)
        elapsed = time.perf_counter() - start
        train_result = evaluate(y_train, pipeline.predict(X_train), labels)
        validation_result = evaluate(y_validation, pipeline.predict(X_validation), validation_labels)
        tree = pipeline.named_steps["model"]
        row = {"max_depth": "unlimited" if depth is None else depth, "min_samples_leaf": min_leaf,
               "fit_seconds": elapsed, "node_count": int(tree.tree_.node_count), "leaf_count": int(tree.get_n_leaves()),
               **{f"train_{key}": value for key, value in train_result.items()},
               **{f"validation_{key}": value for key, value in validation_result.items()}}
        history.append(row)
        pd.DataFrame(history).to_csv(output / "selection_metrics.csv", index=False)
        log(f"depth={row['max_depth']}, min_leaf={min_leaf}: val macro-F1={row['validation_macro_f1']:.6f}, attack recall={row['validation_binary_recall_attack']:.6f}, FPR={row['validation_binary_false_positive_rate']:.6f}, nodes={row['node_count']}")
    # Primary objective: macro-F1. Within 0.5 percentage point of the best,
    # prefer the smaller tree for FPGA implementation.
    best_macro = max(row["validation_macro_f1"] for row in history)
    eligible = [row for row in history if row["validation_macro_f1"] >= best_macro - 0.005]
    selected_row = min(eligible, key=lambda row: (row["node_count"], -row["validation_binary_recall_attack"], row["validation_binary_false_positive_rate"]))
    selected_depth = None if selected_row["max_depth"] == "unlimited" else int(selected_row["max_depth"])
    selected_leaf = int(selected_row["min_samples_leaf"])
    rule = "Highest validation macro-F1; among configurations within 0.005 absolute macro-F1, choose the fewest nodes, then higher attack recall and lower FPR. Fixed before test access."
    write_json(output / "selection.json", {"rule": rule, "best_validation_macro_f1": best_macro,
                                             "selected_max_depth": selected_depth, "selected_min_samples_leaf": selected_leaf,
                                             "selected_result": selected_row})
    development_ids = np.sort(np.concatenate([train_ids, validation_ids]))
    final_model = build_pipeline(selected_depth, selected_leaf).fit(X.iloc[development_ids], y.iloc[development_ids])
    joblib.dump(final_model, output / "pipeline.joblib")
    restored = joblib.load(output / "pipeline.joblib")
    np.testing.assert_array_equal(final_model.predict(X.iloc[development_ids[:100]]), restored.predict(X.iloc[development_ids[:100]]))

    # First and only use of the new held-out split after selection/refit.
    X_test, y_test = X.iloc[list(test_ids)], y.iloc[list(test_ids)]
    predicted = final_model.predict(X_test)
    test_labels = sorted(y_test.unique())
    result = evaluate(y_test, predicted, test_labels)
    report = classification_report(y_test, predicted, labels=labels, output_dict=True, zero_division=0)
    per_class = pd.DataFrame({label: report[label] for label in labels}).T
    per_class["train_support"] = supports.train
    per_class["validation_support"] = supports.validation
    per_class["test_support"] = supports.test
    per_class.to_csv(output / "per_class_metrics.csv", index_label="attack_type")
    matrix = confusion_matrix(y_test, predicted, labels=labels)
    pd.DataFrame(matrix, index=labels, columns=labels).to_csv(output / "confusion_matrix.csv", index_label="actual_type")
    details = pd.DataFrame({"ground_truth_row_zero_based": test_ids, "actual_type": y_test.to_numpy(), "predicted_type": predicted})
    details["error_type"] = np.select([
        details.actual_type == details.predicted_type,
        (details.actual_type == "normal") & (details.predicted_type != "normal"),
        (details.actual_type != "normal") & (details.predicted_type == "normal")],
        ["correct_type", "false_alarm", "missed_attack"], default="wrong_attack_type")
    details.to_csv(output / "test_predictions.csv", index=False)
    details.loc[details.error_type.ne("correct_type")].to_csv(output / "misclassified_records.csv", index=False)
    pairs = details.loc[details.error_type.ne("correct_type")].groupby(["actual_type", "predicted_type", "error_type"]).size().sort_values(ascending=False).rename("count")
    pairs.to_csv(output / "confusion_pairs.csv")
    error_counts = details.error_type.value_counts().to_dict()
    write_json(output / "test_metrics.json", {**result, "error_counts": error_counts})
    tree = final_model.named_steps["model"]
    feature_names = final_model.named_steps["preprocess"].get_feature_names_out()
    pd.DataFrame({"feature": feature_names, "importance": tree.feature_importances_}).sort_values("importance", ascending=False).to_csv(output / "feature_importances.csv", index=False)
    encoder = final_model.named_steps["preprocess"].named_transformers_["categorical"]
    write_json(output / "feature_schema.json", {
        "raw_feature_count": len(FEATURES), "raw_features": FEATURES,
        "categorical_features": CATEGORICAL, "numeric_feature_count": len(NUMERIC),
        "one_hot_categories": {column: values.tolist() for column, values in zip(CATEGORICAL, encoder.categories_)},
        "encoded_feature_count": len(feature_names), "encoded_features": feature_names.tolist(),
        "classes": tree.classes_.tolist(), "excluded": ["label", "difficulty", "source/provenance"],
    })
    node_values = tree.tree_.value[:, 0, :]
    node_frame = pd.DataFrame({
        "node_id": range(tree.tree_.node_count), "left_child": tree.tree_.children_left,
        "right_child": tree.tree_.children_right, "encoded_feature_index": tree.tree_.feature,
        "threshold": tree.tree_.threshold, "impurity": tree.tree_.impurity,
        "sample_count": tree.tree_.n_node_samples,
        "predicted_class": tree.classes_[node_values.argmax(axis=1)],
    })
    node_frame["encoded_feature"] = node_frame.encoded_feature_index.map(
        lambda index: feature_names[index] if index >= 0 else "LEAF"
    )
    node_frame.to_csv(output / "tree_nodes.csv", index=False)
    fig, ax = plt.subplots(figsize=(15, 13))
    normalized = np.divide(matrix, matrix.sum(axis=1, keepdims=True), out=np.zeros_like(matrix, dtype=float), where=matrix.sum(axis=1, keepdims=True) != 0)
    image = ax.imshow(normalized, vmin=0, vmax=1, cmap="Blues")
    ax.set_xticks(range(len(labels)), labels, rotation=90, fontsize=6)
    ax.set_yticks(range(len(labels)), labels, fontsize=6)
    ax.set_xlabel("Predicted type"); ax.set_ylabel("Actual type")
    ax.set_title("Decision Tree on merged ground truth — row-normalized confusion matrix")
    fig.colorbar(image, ax=ax); fig.tight_layout(); fig.savefig(output / "confusion_matrix.png", dpi=160); plt.close(fig)
    metadata = {"model": "DecisionTreeClassifier", "task": "40-class attack-name classification",
                "ground_truth_sha256": sha256(args.ground_truth), "feature_count": len(FEATURES), "class_count": len(labels),
                "seed": SEED, "selection_rule": rule, "selected_max_depth": selected_depth,
                "selected_min_samples_leaf": selected_leaf, "actual_depth": int(tree.get_depth()),
                "node_count": int(tree.tree_.node_count), "leaf_count": int(tree.get_n_leaves()),
                "encoded_feature_count": len(feature_names), "model_file_bytes": (output / "pipeline.joblib").stat().st_size,
                "python": platform.python_version(), "sklearn": sklearn.__version__, "python_executable": sys.executable,
                "split_counts": split.split.value_counts().to_dict(), "classes_absent_from_validation": absent_validation,
                "checks": {"41_features_only": True, "unique_feature_vectors": True, "splits_disjoint_and_complete": True,
                           "selection_before_test": True, "serialization_prediction_parity": True}}
    write_json(output / "run_metadata.json", metadata)
    lines = ["# Decision Tree trên ground truth tổng hợp", "",
             "Ground truth gộp hai file đầy đủ, loại bản sao theo 41 feature và quarantine vector có nhãn xung đột. Difficulty không được dùng làm feature.", "",
             f"Split seed 42: {len(train_ids):,} train / {len(validation_ids):,} validation / {len(test_ids):,} test. Cấu hình chọn trên validation rồi fit lại train+validation; test chỉ được dùng một lần sau lựa chọn.", "",
             f"Cấu hình: max_depth={selected_row['max_depth']}, min_samples_leaf={selected_leaf}, actual_depth={tree.get_depth()}, nodes={tree.tree_.node_count}, leaves={tree.get_n_leaves()}.", "",
             f"Đầu vào có 41 feature gốc: 38 số và 3 category. One-hot của ground truth sạch tạo {len(feature_names)} feature cho cây. `feature_schema.json` lưu mapping; `tree_nodes.csv` lưu node/ngưỡng để chuẩn bị chuyển FPGA.", "",
             "| Test metric | Value |", "|---|---:|",
             *[f"| {key} | {result[key]:.2%} |" for key in ["accuracy", "macro_f1", "weighted_f1", "binary_precision_attack", "binary_recall_attack", "binary_f1_attack", "binary_false_positive_rate"]], "",
             "| Outcome | Count |", "|---|---:|", *[f"| {key} | {value} |" for key, value in error_counts.items()], "",
             "Macro-F1 test tính trên các lớp hiện diện trong test. Các lớp chỉ có 2 mẫu tổng cộng không có validation; xem class_support.csv. Kết quả thuộc split ground truth riêng, không so sánh trực tiếp với benchmark KDDTrain+/KDDTest+ chuẩn.", "",
             "Xem per_class_metrics.csv, confusion_pairs.csv và misclassified_records.csv để đánh giá từng loại lỗi.", "", "![Confusion matrix](confusion_matrix.png)", ""]
    (output / "report_vi.md").write_text("\n".join(lines), encoding="utf-8")
    log(f"Selected depth={selected_row['max_depth']}, min_leaf={selected_leaf}; test metrics={json.dumps(result)}; errors={error_counts}")


if __name__ == "__main__":
    main()
