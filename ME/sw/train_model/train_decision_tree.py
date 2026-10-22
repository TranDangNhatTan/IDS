"""Reproducible NSL-KDD binary Decision Tree baseline; no test-based tuning."""

import argparse
import csv
import hashlib
import json
import platform
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.metrics import ConfusionMatrixDisplay, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.tree import DecisionTreeClassifier

from ME.sw.paths import RAW_DATA_DIR, TREE_DIR


FEATURES = [
    "duration", "protocol_type", "service", "flag", "src_bytes", "dst_bytes",
    "land", "wrong_fragment", "urgent", "hot", "num_failed_logins", "logged_in",
    "num_compromised", "root_shell", "su_attempted", "num_root",
    "num_file_creations", "num_shells", "num_access_files", "num_outbound_cmds",
    "is_host_login", "is_guest_login", "count", "srv_count", "serror_rate",
    "srv_serror_rate", "rerror_rate", "srv_rerror_rate", "same_srv_rate",
    "diff_srv_rate", "srv_diff_host_rate", "dst_host_count", "dst_host_srv_count",
    "dst_host_same_srv_rate", "dst_host_diff_srv_rate", "dst_host_same_src_port_rate",
    "dst_host_srv_diff_host_rate", "dst_host_serror_rate", "dst_host_srv_serror_rate",
    "dst_host_rerror_rate", "dst_host_srv_rerror_rate",
]
CATEGORICAL = ["protocol_type", "service", "flag"]
NUMERIC = [column for column in FEATURES if column not in CATEGORICAL]
DEPTHS = [1, 2, 3, 4, 6, 8, 12]
SEED = 42
SELECTION_RULE = (
    "Maximize validation balanced_accuracy = (attack recall + 1 - FPR) / 2; "
    "break exact ties by smaller max_depth. Fixed before accessing test data."
)


def load_dataset(path):
    # Check each record, including short rows which pandas otherwise pads with NaN.
    with path.open(encoding="utf-8", newline="") as handle:
        for line, row in enumerate(csv.reader(handle), start=1):
            if len(row) != 43:
                raise ValueError(f"{path.name}:{line}: expected 43 fields, got {len(row)}")
    frame = pd.read_csv(path, header=None, names=FEATURES + ["label", "difficulty"])
    if frame.empty or frame.isna().any().any():
        raise ValueError(f"Empty dataset or missing values: {path}")
    X = frame.loc[:, FEATURES].copy()
    X[NUMERIC] = X[NUMERIC].apply(pd.to_numeric, errors="raise")
    if not np.isfinite(X[NUMERIC].to_numpy()).all():
        raise ValueError(f"Non-finite numeric features: {path}")
    # NSL-KDD TXT labels have no terminal period. Whitespace is not meaningful.
    y = frame["label"].str.strip().ne("normal").astype("int8").rename("attack")
    if set(y.unique()) != {0, 1}:
        raise ValueError(f"Expected both normal and attack classes: {path}")
    return X, y


def build_pipeline(depth):
    preprocess = ColumnTransformer([
        ("categorical", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL),
        ("numeric", "passthrough", NUMERIC),
    ], remainder="drop")
    return Pipeline([
        ("preprocess", preprocess),
        ("model", DecisionTreeClassifier(max_depth=depth, random_state=SEED)),
    ])


def metrics(y_true, y_pred):
    tn, fp, fn, tp = (int(value) for value in confusion_matrix(
        y_true, y_pred, labels=[0, 1]
    ).ravel())
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    fpr = fp / (fp + tn) if fp + tn else 0.0
    return {
        "precision_attack": precision,
        "recall_attack": recall,
        "f1_attack": 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0,
        "false_positive_rate": fpr,
        "accuracy": (tp + tn) / (tn + fp + fn + tp),
        "balanced_accuracy": (recall + 1 - fpr) / 2,
        "tn": tn, "fp": fp, "fn": fn, "tp": tp,
    }


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def class_counts(y):
    return {"total": len(y), "normal": int((y == 0).sum()), "attack": int((y == 1).sum())}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def plot_progress(history, depth, output):
    figure, axes = plt.subplots(1, 2, figsize=(12, 4.5))
    axes[0].plot(history.max_depth, history.train_f1_attack, "o-", label="Train F1 (attack)")
    axes[0].plot(history.max_depth, history.validation_f1_attack, "o-", label="Validation F1 (attack)")
    axes[0].set_ylabel("F1")
    axes[1].plot(history.max_depth, history.validation_recall_attack, "o-", label="Validation recall (attack)")
    axes[1].plot(history.max_depth, history.validation_false_positive_rate, "o-", label="Validation FPR")
    axes[1].plot(history.max_depth, history.validation_balanced_accuracy, "o-", label="Validation balanced accuracy")
    axes[1].set_ylabel("Metric")
    for axis in axes:
        axis.axvline(depth, color="gray", linestyle="--", label=f"Selected depth: {depth}")
        axis.set_xlabel("max_depth (separate model fits, not epochs)")
        axis.set_xticks(DEPTHS)
        axis.set_ylim(0, 1.02)
        axis.grid(alpha=0.25)
        axis.legend(fontsize=8)
    figure.tight_layout()
    figure.savefig(output / "depth_metrics.png", dpi=180)
    plt.close(figure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=TREE_DIR / "decision_tree")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    # Preserve previous evidence; never overwrite an existing training run.
    output.mkdir(parents=True, exist_ok=False)

    def log(message):
        print(message, flush=True)
        with (output / "training.log").open("a", encoding="utf-8") as handle:
            handle.write(message + "\n")

    log(f"Selection rule: {SELECTION_RULE}")
    log(f"Python executable: {sys.executable}; virtual environment: {sys.prefix != sys.base_prefix}")
    X, y = load_dataset(args.data_dir / "KDDTrain+.txt")
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, stratify=y, random_state=SEED
    )
    assert set(X_train.index).isdisjoint(X_val.index)
    assert len(X_train) + len(X_val) == len(X)
    split = pd.Series("train", index=X.index, name="split")
    split.loc[X_val.index] = "validation"
    split.to_csv(output / "split_assignments.csv", index_label="source_row_zero_based")
    log(f"Train: {class_counts(y_train)}; validation: {class_counts(y_val)}")

    rows = []
    for depth in DEPTHS:
        pipeline = build_pipeline(depth)
        started = time.perf_counter()
        pipeline.fit(X_train, y_train)
        elapsed = time.perf_counter() - started
        encoder = pipeline.named_steps["preprocess"].named_transformers_["categorical"]
        for column, categories in zip(CATEGORICAL, encoder.categories_):
            assert set(categories) == set(X_train[column].unique())
        row = {"max_depth": depth, "fit_seconds": elapsed}
        for prefix, inputs, labels in [("train", X_train, y_train), ("validation", X_val, y_val)]:
            row.update({f"{prefix}_{key}": value for key, value in metrics(labels, pipeline.predict(inputs)).items()})
        row["node_count"] = pipeline.named_steps["model"].tree_.node_count
        row["leaf_count"] = int(pipeline.named_steps["model"].get_n_leaves())
        rows.append(row)
        pd.DataFrame(rows).to_csv(output / "depth_metrics.csv", index=False)
        log(f"max_depth={depth:2d} | train F1={row['train_f1_attack']:.6f} | "
            f"val F1={row['validation_f1_attack']:.6f} | recall={row['validation_recall_attack']:.6f} | "
            f"FPR={row['validation_false_positive_rate']:.6f} | "
            f"balanced_accuracy={row['validation_balanced_accuracy']:.6f}")

    best = max(rows, key=lambda row: (row["validation_balanced_accuracy"], -row["max_depth"]))
    depth = best["max_depth"]
    write_json(output / "selection.json", {"rule": SELECTION_RULE, "selected_max_depth": depth, "validation_result": best})
    log(f"Selected max_depth={depth} using validation only. Refitting all {len(X)} training records.")
    final_pipeline = build_pipeline(depth).fit(X, y)
    joblib.dump(final_pipeline, output / "decision_tree_pipeline.joblib")
    # Check serialization and unseen categorical handling without accessing test.
    restored = joblib.load(output / "decision_tree_pipeline.joblib")
    sample = X.iloc[:128].copy()
    np.testing.assert_array_equal(final_pipeline.predict(sample), restored.predict(sample))
    sample.loc[:, CATEGORICAL] = "__unseen_category_check__"
    assert len(restored.predict(sample)) == len(sample)
    assert list(restored.feature_names_in_) == FEATURES
    feature_names = final_pipeline.named_steps["preprocess"].get_feature_names_out()
    tree = final_pipeline.named_steps["model"]
    pd.DataFrame({"feature": feature_names, "importance": tree.feature_importances_}).sort_values(
        "importance", ascending=False
    ).to_csv(output / "feature_importances.csv", index=False)
    write_json(output / "feature_schema.json", {
        "input_features": FEATURES, "categorical_features": CATEGORICAL,
        "excluded_fields": ["label", "difficulty"],
        "transformed_features": feature_names.tolist(), "class_mapping": {"0": "normal", "1": "attack"},
        "categories": {column: values.tolist() for column, values in zip(
            CATEGORICAL, final_pipeline.named_steps["preprocess"].named_transformers_["categorical"].categories_
        )},
    })

    # First access to test data is AFTER model selection, final fit and persistence.
    log("Evaluating the fixed final model on KDDTest+.txt once.")
    X_test, y_test = load_dataset(args.data_dir / "KDDTest+.txt")
    predictions = final_pipeline.predict(X_test)
    final_metrics = metrics(y_test, predictions)
    matrix = [[final_metrics["tn"], final_metrics["fp"]], [final_metrics["fn"], final_metrics["tp"]]]
    write_json(output / "test_metrics.json", {
        **final_metrics, "confusion_matrix": matrix,
        "confusion_matrix_order": ["normal", "attack"], "rows": "actual", "columns": "predicted",
    })
    pd.DataFrame(matrix, index=["actual_normal", "actual_attack"], columns=["predicted_normal", "predicted_attack"]).to_csv(output / "confusion_matrix.csv")
    pd.DataFrame({"actual": y_test, "predicted": predictions}).to_csv(output / "test_predictions.csv", index_label="source_row_zero_based")
    fig, ax = plt.subplots(figsize=(5, 4))
    ConfusionMatrixDisplay(np.array(matrix), display_labels=["normal", "attack"]).plot(ax=ax, colorbar=False, values_format="d")
    ax.set_title(f"Final KDDTest+ evaluation (max_depth={depth})")
    fig.tight_layout()
    fig.savefig(output / "confusion_matrix.png", dpi=180)
    plt.close(fig)
    plot_progress(pd.DataFrame(rows), depth, output)

    metadata = {
        "completed_at_utc": datetime.now(timezone.utc).isoformat(),
        "python_executable": sys.executable, "virtual_environment": sys.prefix != sys.base_prefix,
        "seed": SEED, "validation_fraction": 0.2, "stratified": True,
        "candidate_depths": DEPTHS, "selection_rule": SELECTION_RULE,
        "selected_max_depth": depth,
        "data_counts": {"train": class_counts(y_train), "validation": class_counts(y_val), "full_train": class_counts(y), "test": class_counts(y_test)},
        "sha256": {name: sha256(args.data_dir / name) for name in ["KDDTrain+.txt", "KDDTest+.txt"]},
        "versions": {"python": platform.python_version(), "numpy": np.__version__, "pandas": pd.__version__, "scikit-learn": sklearn.__version__, "matplotlib": matplotlib.__version__, "joblib": joblib.__version__},
        "final_model": {"actual_depth": int(tree.get_depth()), "node_count": int(tree.tree_.node_count), "leaf_count": int(tree.get_n_leaves()), "encoded_feature_count": len(feature_names), "parameters": tree.get_params()},
        "checks": {"split_disjoint": True, "encoder_fitted_on_train_only_during_selection": True, "serialization_prediction_parity": True, "unseen_categories_supported": True, "input_schema_41_features": True},
    }
    write_json(output / "run_metadata.json", metadata)
    report = [
        "# NSL-KDD Decision Tree baseline", "",
        f"Selected max_depth: **{depth}**. {SELECTION_RULE}", "",
        f"Stratified split, seed 42: {len(X_train):,} train / {len(X_val):,} validation. Final refit: {len(X):,} records. Test: {len(X_test):,} records.", "",
        "41 input features; one-hot encode protocol_type/service/flag with unknown categories ignored. Label and difficulty excluded.", "",
        "## Model selection (depths, not epochs)", "",
        "| max_depth | Train F1 attack | Validation F1 attack | Validation recall attack | Validation FPR | Validation balanced accuracy |",
        "|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        report.append(f"| {row['max_depth']} | {row['train_f1_attack']:.6f} | {row['validation_f1_attack']:.6f} | {row['validation_recall_attack']:.6f} | {row['validation_false_positive_rate']:.6f} | {row['validation_balanced_accuracy']:.6f} |")
    report += ["", "![Depth metrics](depth_metrics.png)", "", "## Final test (one evaluation, no retuning)", "", "| Metric | Value |", "|---|---:|"]
    for key in ["precision_attack", "recall_attack", "f1_attack", "false_positive_rate", "accuracy", "balanced_accuracy"]:
        report.append(f"| {key} | {final_metrics[key]:.6%} |")
    report += ["", "Confusion matrix: rows = actual, columns = predicted; order = normal, attack.", "", "```text", str(np.array(matrix)), "```", "", "![Confusion matrix](confusion_matrix.png)", "",
        f"Final tree: {tree.tree_.node_count} nodes, {tree.get_n_leaves()} leaves, {len(feature_names)} encoded features.", "",
        "Validation and test results describe different data splits; the test result must not be used to tune this baseline. Any later test-driven changes require a new independent evaluation set.", "",
        "Checks passed: disjoint complete split, training-only encoder categories during selection, saved-model prediction parity, unknown-category inference, 41-column input schema.", ""]
    (output / "report.md").write_text("\n".join(report), encoding="utf-8")
    log(f"Final test metrics: {json.dumps(final_metrics)}")
    log(f"Artifacts saved to: {output}")


if __name__ == "__main__":
    main()
