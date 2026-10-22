"""Shared, fixed evaluation protocol for Decision Tree / Random Forest comparison."""

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
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.tree import DecisionTreeClassifier

from ME.sw.paths import RAW_DATA_DIR, TREE_DIR
from ME.sw.train_model.train_decision_tree import FEATURES, CATEGORICAL, NUMERIC, SEED, load_dataset, metrics, plt, sha256, write_json


RULE = "Highest validation macro-F1 across all training classes; exact ties prefer shallower depth. Test is an already-viewed benchmark, not an untouched holdout."


def stratified_indices(y, fraction=0.2, seed=SEED):
    """Exact-size stratification with at least one train/validation row per class."""
    counts = y.value_counts().sort_index()
    if counts.min() < 2:
        raise ValueError("Every class needs at least two examples for this protocol")
    target = math.ceil(len(y) * fraction)
    ideal = counts * fraction
    allocated = np.floor(ideal).astype(int).clip(lower=1)
    allocated = allocated.clip(upper=counts - 1)
    if target < len(counts) or target > len(y) - len(counts):
        raise ValueError("Split size cannot represent every class in both partitions")
    while allocated.sum() < target:
        candidates = (ideal - allocated).where(allocated < counts - 1, -np.inf)
        allocated.loc[candidates.idxmax()] += 1
    while allocated.sum() > target:
        candidates = (allocated - ideal).where(allocated > 1, -np.inf)
        allocated.loc[candidates.idxmax()] -= 1
    rng = np.random.default_rng(seed)
    train, validation = [], []
    for label in counts.index:
        positions = np.flatnonzero(y.to_numpy() == label)
        rng.shuffle(positions)
        size = int(allocated[label])
        validation.extend(positions[:size])
        train.extend(positions[size:])
    return np.sort(train), np.sort(validation)


def build_model(kind, depth, jobs=4):
    preprocess = ColumnTransformer([
        ("categorical", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL),
        ("numeric", "passthrough", NUMERIC),
    ])
    params = dict(max_depth=depth, random_state=SEED, class_weight="balanced", criterion="gini")
    estimator = DecisionTreeClassifier(**params) if kind == "decision_tree" else RandomForestClassifier(
        **params, n_estimators=200, n_jobs=jobs, max_features="sqrt"
    )
    return Pipeline([("preprocess", preprocess), ("model", estimator)])


def score(y, predicted, labels):
    binary = metrics(np.asarray(y) != "normal", np.asarray(predicted) != "normal")
    return {
        "accuracy": float(accuracy_score(y, predicted)),
        "macro_f1": float(f1_score(y, predicted, labels=labels, average="macro", zero_division=0)),
        "weighted_f1": float(f1_score(y, predicted, labels=labels, average="weighted", zero_division=0)),
        **{f"binary_{name}": value for name, value in binary.items()},
    }


def main(kind):
    parser = argparse.ArgumentParser(description=f"Train {kind} to predict exact attack names")
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=TREE_DIR / f"{kind}_multiclass")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=False)

    def log(message):
        print(message, flush=True)
        with (output / "training.log").open("a", encoding="utf-8") as handle:
            handle.write(message + "\n")

    log(f"{kind} multiclass; executable={sys.executable}; venv={sys.prefix != sys.base_prefix}")
    log(RULE)
    X, _ = load_dataset(args.data_dir / "KDDTrain+.txt")
    y = pd.read_csv(args.data_dir / "KDDTrain+.txt", header=None, usecols=[41]).iloc[:, 0].str.strip()
    train_ids, val_ids = stratified_indices(y)
    X_train, X_val = X.iloc[train_ids], X.iloc[val_ids]
    y_train, y_val = y.iloc[train_ids], y.iloc[val_ids]
    labels = sorted(y.unique())
    assert not set(train_ids) & set(val_ids)
    assert set(y_train.unique()) == set(y_val.unique()) == set(labels)
    split = pd.DataFrame({"source_row_zero_based": range(len(X)), "split": "train", "actual_type": y})
    split.loc[val_ids, "split"] = "validation"
    split.to_csv(output / "split_assignments.csv", index=False)
    counts = pd.DataFrame({"full_train": y.value_counts(), "train": y_train.value_counts(), "validation": y_val.value_counts()}).sort_index()
    counts.to_csv(output / "class_support.csv", index_label="attack_type")
    log(f"train={len(train_ids)}, validation={len(val_ids)}, classes={len(labels)}; every class present in both partitions")
    candidates = [4, 8, 12, 20, None] if kind == "decision_tree" else [12, 20, None]
    history, validation_predictions = [], {}
    for depth in candidates:
        key = "unlimited" if depth is None else str(depth)
        model = build_model(kind, depth, args.jobs)
        start = time.perf_counter()
        model.fit(X_train, y_train)
        fit_seconds = time.perf_counter() - start
        val_pred = model.predict(X_val)
        validation_predictions[key] = val_pred
        row = {"max_depth": key, "fit_seconds": fit_seconds}
        for prefix, truth, prediction in [("train", y_train, model.predict(X_train)), ("validation", y_val, val_pred)]:
            row.update({f"{prefix}_{name}": value for name, value in score(truth, prediction, labels).items()})
        history.append(row)
        pd.DataFrame(history).to_csv(output / "selection_metrics.csv", index=False)
        log(f"depth={key}: train macro-F1={row['train_macro_f1']:.6f}; validation macro-F1={row['validation_macro_f1']:.6f}; weighted-F1={row['validation_weighted_f1']:.6f}; fit={fit_seconds:.2f}s")
    best = max(history, key=lambda row: (row["validation_macro_f1"], -(int(row["max_depth"]) if row["max_depth"] != "unlimited" else math.inf)))
    selected = None if best["max_depth"] == "unlimited" else int(best["max_depth"])
    write_json(output / "selection.json", {"rule": RULE, "selected_max_depth": selected, "result": best})
    pd.DataFrame({"source_row_zero_based": val_ids, "actual_type": y_val.to_numpy(), "predicted_type": validation_predictions[best["max_depth"]]}).to_csv(output / "validation_predictions.csv", index=False)
    validation_report = classification_report(y_val, validation_predictions[best["max_depth"]], labels=labels, output_dict=True, zero_division=0)
    pd.DataFrame(validation_report).T.to_csv(output / "validation_classification_report.csv", index_label="class_or_average")
    log(f"Selected depth={best['max_depth']}; fitting all KDDTrain+ records")
    model = build_model(kind, selected, args.jobs)
    start = time.perf_counter()
    model.fit(X, y)
    final_fit_seconds = time.perf_counter() - start
    joblib.dump(model, output / "pipeline.joblib")
    restored = joblib.load(output / "pipeline.joblib")
    np.testing.assert_array_equal(model.predict(X.iloc[:100]), restored.predict(X.iloc[:100]))
    unseen_sample = X.iloc[:2].copy()
    unseen_sample.loc[:, CATEGORICAL] = "__new_category__"
    assert len(restored.predict(unseen_sample)) == 2
    del restored
    names = model.named_steps["preprocess"].get_feature_names_out()
    pd.DataFrame({"feature": names, "importance": model.named_steps["model"].feature_importances_}).sort_values("importance", ascending=False).to_csv(output / "feature_importances.csv", index=False)
    write_json(output / "feature_schema.json", {"input_features": FEATURES, "encoded_features": names.tolist(), "classes": labels})

    log("One evaluation of this selected model on the previously viewed KDDTest+ benchmark")
    X_test, _ = load_dataset(args.data_dir / "KDDTest+.txt")
    y_test = pd.read_csv(args.data_dir / "KDDTest+.txt", header=None, usecols=[41]).iloc[:, 0].str.strip()
    start = time.perf_counter()
    predicted = model.predict(X_test)
    predict_seconds = time.perf_counter() - start
    # Overall macro-F1 includes the union of training and test labels, including
    # unseen test classes and training-only classes. Also report test-present macro.
    all_labels = sorted(set(labels) | set(y_test))
    report = classification_report(y_test, predicted, labels=all_labels, output_dict=True, zero_division=0)
    per_class = pd.DataFrame({label: report[label] for label in all_labels}).T
    per_class["support"] = per_class.support.astype(int)
    per_class["train_support"] = [int(y.eq(label).sum()) for label in all_labels]
    per_class["seen_in_train"] = per_class.train_support.gt(0)
    per_class["predicted_count"] = [int(np.count_nonzero(predicted == label)) for label in all_labels]
    per_class.to_csv(output / "per_class_metrics.csv", index_label="attack_type")
    cm = confusion_matrix(y_test, predicted, labels=all_labels)
    pd.DataFrame(cm, index=all_labels, columns=all_labels).to_csv(output / "confusion_matrix.csv", index_label="actual_type")
    results = score(y_test, predicted, all_labels)
    results["macro_f1_test_present_classes"] = float(f1_score(y_test, predicted, labels=sorted(y_test.unique()), average="macro", zero_division=0))
    results["macro_f1_label_scope"] = "Union of train and test classes, zero_division=0; see per_class_metrics.csv for support"
    seen_mask = y_test.isin(labels).to_numpy()
    for prefix, mask in [("seen", seen_mask), ("unseen", ~seen_mask)]:
        results[f"{prefix}_test_samples"] = int(mask.sum())
        results[f"{prefix}_exact_type_accuracy"] = float(np.mean(predicted[mask] == y_test.to_numpy()[mask])) if mask.any() else None
        attack_mask = mask & y_test.ne("normal").to_numpy()
        results[f"{prefix}_attack_detection_recall"] = float(np.mean(predicted[attack_mask] != "normal")) if attack_mask.any() else None
    results["unseen_test_labels"] = sorted(set(y_test) - set(labels))
    write_json(output / "test_metrics.json", results)
    actual_array = y_test.to_numpy()
    outcomes = np.select([
        actual_array == predicted,
        (actual_array == "normal") & (predicted != "normal"),
        (actual_array != "normal") & (predicted == "normal"),
    ], ["correct_type", "false_alarm", "missed_attack"], default="wrong_attack_type")
    details = X_test.copy()
    details.insert(0, "source_line_one_based", np.arange(len(X_test)) + 1)
    details.insert(1, "actual_type", actual_array)
    details.insert(2, "predicted_type", predicted)
    details.insert(3, "error_type", outcomes)
    details.insert(4, "actual_type_seen_in_train", seen_mask)
    details.to_csv(output / "test_predictions.csv", index=False)
    errors = details.loc[details.error_type.ne("correct_type")]
    errors.to_csv(output / "misclassified_records.csv", index=False)
    pairs = errors.groupby(["actual_type", "predicted_type", "error_type"]).size().sort_values(ascending=False).rename("count")
    pairs.to_csv(output / "confusion_pairs.csv")
    error_counts = details.error_type.value_counts().to_dict()
    write_json(output / "error_counts.json", error_counts)
    fig, ax = plt.subplots(figsize=(14, 12))
    normalized = np.divide(cm, cm.sum(axis=1, keepdims=True), out=np.zeros_like(cm, dtype=float), where=cm.sum(axis=1, keepdims=True) != 0)
    picture = ax.imshow(normalized, vmin=0, vmax=1, cmap="Blues")
    ax.set_xticks(range(len(all_labels)), all_labels, rotation=90, fontsize=7)
    ax.set_yticks(range(len(all_labels)), all_labels, fontsize=7)
    ax.set_xlabel("Predicted attack type")
    ax.set_ylabel("Actual attack type")
    ax.set_title(f"{kind}: confusion matrix normalized by actual class\nZero-support rows are blank; see CSV for counts")
    fig.colorbar(picture, ax=ax)
    fig.tight_layout()
    fig.savefig(output / "confusion_matrix.png", dpi=160)
    plt.close(fig)
    estimator = model.named_steps["model"]
    trees = [estimator] if kind == "decision_tree" else estimator.estimators_
    run = {
        "model": kind, "task": "exact_attack_type_multiclass", "random_seed": SEED,
        "python_executable": sys.executable, "virtual_environment": sys.prefix != sys.base_prefix,
        "python_version": platform.python_version(), "sklearn_version": sklearn.__version__,
        "selection_rule": RULE, "selected_max_depth": selected, "candidate_depths": candidates,
        "split": "80/20 stratified by original label; minimum one example per class in each partition; largest-remainder allocation; seed 42",
        "train_rows": len(train_ids), "validation_rows": len(val_ids), "training_classes": labels,
        "model_parameters": estimator.get_params(), "final_fit_seconds": final_fit_seconds,
        "test_predict_seconds": predict_seconds, "tree_count": len(trees),
        "total_nodes": sum(int(t.tree_.node_count) for t in trees),
        "total_leaves": sum(int(t.get_n_leaves()) for t in trees),
        "model_file_bytes": (output / "pipeline.joblib").stat().st_size,
        "sha256": {name: sha256(args.data_dir / name) for name in ["KDDTrain+.txt", "KDDTest+.txt"]},
        "split_sha256": sha256(output / "split_assignments.csv"),
        "test_status": "Previously viewed benchmark; not an independent untouched holdout",
        "checks": {"split_disjoint": True, "all_classes_in_both_partitions": True, "serialization_predictions_match": True, "unseen_categories_supported": True},
    }
    write_json(output / "run_metadata.json", run)
    lines = [f"# {kind} — dự đoán tên loại tấn công", "",
        f"Model chọn bằng validation macro-F1: max_depth={best['max_depth']}; macro-F1 validation={best['validation_macro_f1']:.2%}.", "",
        "Cả hai model dùng cùng split 80/20, seed 42, nhãn gốc đa lớp, one-hot chỉ fit trên train khi chọn cấu hình, class_weight=balanced. Split có ít nhất một mẫu mỗi lớp trong cả train/validation; lớp rất hiếm có 1 mẫu validation nên metric có độ bất định lớn.", "",
        "KDDTest+ là benchmark đã xem ở lần chạy trước. Không dùng kết quả của lần đánh giá này để đổi cấu hình. Cần dữ liệu độc lập mới để đánh giá phiên bản được phát triển sau khi đã xem benchmark.", "",
        f"Train có {len(labels)} lớp; test có {len(results['unseen_test_labels'])} nhãn chưa xuất hiện trong train, tổng {results['unseen_test_samples']} mẫu. Model phân loại đóng không thể dự đoán đúng tên lớp chưa được học.", "",
        "## Metric đa lớp", "", "| Metric | Giá trị |", "|---|---:|",
        *[f"| {name} | {results[name]:.2%} |" for name in ["accuracy", "macro_f1", "macro_f1_test_present_classes", "weighted_f1"]], "",
        "Macro-F1 mặc định tính trên hợp các nhãn train/test (kể cả lớp không có mẫu test); có thêm macro-F1 chỉ trên lớp hiện diện trong test. Weighted-F1 có trọng số theo support nên dễ bị lớp lớn chi phối.", "",
        "## Phát hiện có tấn công (gộp từ dự đoán đa lớp)", "", "| Metric | Giá trị |", "|---|---:|",
        *[f"| {name} | {results['binary_' + name]:.2%} |" for name in ["precision_attack", "recall_attack", "f1_attack", "false_positive_rate", "accuracy"]], "",
        "## Các kiểu lỗi", "", *[f"- {name}: {value}" for name, value in error_counts.items()], "",
        "`false_alarm`: normal bị gọi thành tấn công. `missed_attack`: tấn công bị gọi normal. `wrong_attack_type`: phát hiện có tấn công nhưng gọi sai tên loại. `correct_type`: đúng tên loại (bao gồm normal).", "",
        "## Precision / recall / F1 từng loại", "", "| Nhãn | Precision | Recall | F1 | Test support | Train support |", "|---|---:|---:|---:|---:|---:|",
        *[f"| {label} | {row.precision:.2%} | {row.recall:.2%} | {row['f1-score']:.2%} | {int(row.support)} | {int(row.train_support)} |" for label, row in per_class.iterrows()], "",
        "![Confusion matrix](confusion_matrix.png)", "",
        "Xem `confusion_pairs.csv` để biết loại A bị gọi thành loại B bao nhiêu lần; `misclassified_records.csv` có từng dòng sai, nhãn thật/dự đoán và 41 đặc trưng. `source_line_one_based` trỏ tới dòng trong KDDTest+.txt.", "",
        f"Số cây: {len(trees)}; tổng node: {run['total_nodes']}; dung lượng model: {run['model_file_bytes']} byte. Thời gian fit cuối: {final_fit_seconds:.2f}s; dự đoán test: {predict_seconds:.3f}s. Thời gian trên CPU này không phải benchmark FPGA.", ""]
    (output / "report_vi.md").write_text("\n".join(lines), encoding="utf-8")
    log(f"Test exact-type accuracy={results['accuracy']:.6f}; macro-F1={results['macro_f1']:.6f}; weighted-F1={results['weighted_f1']:.6f}")
    log(f"Errors: {error_counts}; saved to {output}")


if __name__ == "__main__":
    raise SystemExit("Use train_decision_tree_multiclass.py or train_random_forest_multiclass.py")
