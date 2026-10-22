"""Compare completed runs without retraining or re-evaluating test data."""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from ME.sw.paths import TREE_DIR
from ME.sw.train_model.train_decision_tree import plt, write_json


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision-tree-dir", type=Path, default=TREE_DIR / "decision_tree_multiclass")
    parser.add_argument("--random-forest-dir", type=Path, default=TREE_DIR / "random_forest_multiclass")
    parser.add_argument("--output-dir", type=Path, default=TREE_DIR / "model_comparison")
    args = parser.parse_args()
    runs = {"decision_tree": args.decision_tree_dir, "random_forest": args.random_forest_dir}
    metadata = {name: read_json(path / "run_metadata.json") for name, path in runs.items()}
    dt, rf = metadata.values()
    for field in ["sha256", "split_sha256", "task", "training_classes", "selection_rule"]:
        if dt[field] != rf[field]:
            raise ValueError(f"Runs are not comparable: {field} differs")
    all_results, rows, reports, error_counts = {}, [], {}, {}
    for name, path in runs.items():
        results = read_json(path / "test_metrics.json")
        selection = read_json(path / "selection.json")
        errors = read_json(path / "error_counts.json")
        all_results[name] = results
        error_counts[name] = errors
        row = {"model": name, "selected_max_depth": selection["selected_max_depth"] if selection["selected_max_depth"] is not None else "unlimited",
               "validation_macro_f1": selection["result"]["validation_macro_f1"]}
        row.update({key: value for key, value in results.items() if isinstance(value, (int, float))})
        row.update({f"count_{key}": errors.get(key, 0) for key in ["correct_type", "false_alarm", "missed_attack", "wrong_attack_type"]})
        row.update({key: metadata[name][key] for key in ["tree_count", "total_nodes", "total_leaves", "model_file_bytes", "final_fit_seconds", "test_predict_seconds"]})
        rows.append(row)
        reports[name] = pd.read_csv(path / "per_class_metrics.csv").set_index("attack_type")
    summary = pd.DataFrame(rows).set_index("model")
    per_class = reports["decision_tree"][["support", "train_support", "seen_in_train"]].copy()
    for name, report in reports.items():
        for metric in ["precision", "recall", "f1-score", "predicted_count"]:
            per_class[f"{name}_{metric}"] = report[metric]
    per_class["rf_minus_dt_f1"] = per_class["random_forest_f1-score"] - per_class["decision_tree_f1-score"]
    output = args.output_dir
    # This directory contains derived comparisons only; regenerating it never
    # changes the preserved model runs or performs another test prediction.
    output.mkdir(parents=True, exist_ok=True)
    summary.to_csv(output / "comparison.csv")
    per_class.to_csv(output / "per_class_comparison.csv")
    write_json(output / "comparison_checks.json", {"same_training_data": True, "same_test_data": True,
        "same_train_validation_split": True, "same_target_classes": True, "same_selection_metric": True,
        "test_is_previously_viewed_benchmark": True, "source_runs": {name: str(path.resolve()) for name, path in runs.items()}})
    names = ["Exact-type\naccuracy", "Macro-F1\n(test-present classes)", "Weighted-F1", "Binary attack\nrecall", "False-positive\nrate"]
    keys = ["accuracy", "macro_f1_test_present_classes", "weighted_f1", "binary_recall_attack", "binary_false_positive_rate"]
    x = np.arange(len(keys))
    fig, ax = plt.subplots(figsize=(11, 5))
    for i, (name, results) in enumerate(all_results.items()):
        bars = ax.bar(x + (i - 0.5) * 0.36, [100 * results[key] for key in keys], 0.36, label=name)
        ax.bar_label(bars, fmt="%.1f", fontsize=8)
    ax.set_xticks(x, names)
    ax.set_ylim(0, 108)
    ax.set_ylabel("Percent; lower is better only for false-positive rate")
    ax.set_title("Multiclass Decision Tree vs Random Forest — previously viewed KDDTest+ benchmark")
    ax.legend()
    fig.tight_layout()
    fig.savefig(output / "comparison.png", dpi=170)
    plt.close(fig)
    percent_rows = {
        "validation_macro_f1": "Macro-F1 validation (23 lớp)",
        "accuracy": "Accuracy đúng tên loại (test)",
        "macro_f1_test_present_classes": "Macro-F1 trên 38 lớp hiện diện trong test",
        "macro_f1": "Macro-F1 hợp nhãn train/test (40 lớp)",
        "weighted_f1": "Weighted-F1 (test)",
        "binary_precision_attack": "Precision phát hiện attack",
        "binary_recall_attack": "Recall phát hiện attack",
        "binary_f1_attack": "F1 phát hiện attack",
        "binary_false_positive_rate": "FPR trên normal",
        "seen_exact_type_accuracy": "Accuracy đúng tên trên mẫu có nhãn đã học",
        "unseen_exact_type_accuracy": "Accuracy đúng tên trên mẫu có nhãn chưa học",
    }
    # Derive label counts rather than assuming a particular copy of NSL-KDD.
    percent_rows["macro_f1_test_present_classes"] = f"Macro-F1 trên {int((per_class.support > 0).sum())} lớp hiện diện trong test"
    percent_rows["macro_f1"] = f"Macro-F1 hợp nhãn train/test ({len(per_class)} lớp)"
    confusion_sections = []
    for name, path in runs.items():
        top_pairs = pd.read_csv(path / "confusion_pairs.csv").head(10)
        confusion_sections += [f"### {name}: 10 cặp nhầm nhiều nhất", "",
            "| Nhãn thật | Dự đoán | Loại lỗi | Số mẫu |", "|---|---|---|---:|",
            *[f"| {row.actual_type} | {row.predicted_type} | {row.error_type} | {row.count} |" for row in top_pairs.itertuples(index=False)], ""]
    lines = ["# So sánh Decision Tree và Random Forest đa lớp", "",
        "Cả hai model dự đoán tên loại tấn công, dùng cùng 41 đặc trưng, cùng split và cùng tiêu chí chọn macro-F1 validation. Model đã fit lại toàn bộ KDDTrain+ sau lựa chọn. Các file run_metadata.json lưu checksum và cấu hình.", "",
        "KDDTest+ đã được xem ở baseline trước; số liệu dưới đây là benchmark tham khảo. Không lựa chọn lại cấu hình theo bảng này. Một đánh giá độc lập cho phiên bản mới cần dữ liệu mới chưa dùng trong phát triển.", "",
        "| Chỉ số | Decision Tree | Random Forest |", "|---|---:|---:|",
        *[f"| {label} | {summary.loc['decision_tree', key]:.2%} | {summary.loc['random_forest', key]:.2%} |" for key, label in percent_rows.items()], "",
        "![So sánh](comparison.png)", "",
        "## Mỗi kiểu lỗi là gì?", "",
        "| Loại kết quả | Ý nghĩa | Decision Tree | Random Forest |", "|---|---|---:|---:|",
        *[f"| {code} | {meaning} | {error_counts['decision_tree'].get(code, 0)} | {error_counts['random_forest'].get(code, 0)} |" for code, meaning in [
            ("correct_type", "Đúng tên loại, kể cả normal"), ("false_alarm", "Normal bị gọi là tấn công"),
            ("missed_attack", "Tấn công bị gọi là normal"), ("wrong_attack_type", "Phát hiện attack nhưng gọi sai tên loại")]], "",
        "Một mẫu neptune bị dự đoán satan là sai đa lớp, nhưng vẫn là phát hiện attack đúng khi gộp nhị phân. Vì thế metric phát hiện và metric đúng tên loại phải được đọc riêng.", "",
        *confusion_sections,
        "## So sánh từng loại", "", "| Nhãn | Train support | Test support | DT recall | RF recall | DT F1 | RF F1 |", "|---|---:|---:|---:|---:|---:|---:|",
        *[f"| {name} | {int(row.train_support)} | {int(row.support)} | {row.decision_tree_recall:.2%} | {row.random_forest_recall:.2%} | {row['decision_tree_f1-score']:.2%} | {row['random_forest_f1-score']:.2%} |" for name, row in per_class.iterrows()], "",
        "Các nhãn có train support = 0 chưa được học; recall đúng tên bằng 0 không có nghĩa model luôn bỏ sót mọi mẫu đó — model có thể gọi chúng là một loại tấn công khác. Các lớp có support rất nhỏ không đủ để kết luận vững chắc. Macro-F1 cân bằng trọng số các lớp; weighted-F1 ưu tiên lớp nhiều mẫu.", "",
        "## Chi phí model", "", "| Đại lượng | Decision Tree | Random Forest |", "|---|---:|---:|",
        *[f"| {key} | {summary.loc['decision_tree', key]} | {summary.loc['random_forest', key]} |" for key in ["tree_count", "total_nodes", "total_leaves", "model_file_bytes", "final_fit_seconds", "test_predict_seconds"]], "",
        "Thời gian đo trên CPU trong lần chạy này, không phải độ trễ FPGA; chưa có benchmark lặp lại. Random Forest 200 cây có chi phí lưu trữ/tính toán lớn hơn một cây. Bảng này so sánh các cấu hình đã thử, không khẳng định thuật toán nào luôn tốt hơn.", "",
        "Chi tiết mẫu sai: `../decision_tree_multiclass/misclassified_records.csv` và `../random_forest_multiclass/misclassified_records.csv`. Bảng cặp nhầm: `confusion_pairs.csv` trong từng thư mục. Chỉ số dòng là dòng gốc trong KDDTest+.txt.", ""]
    (output / "report_vi.md").write_text("\n".join(lines), encoding="utf-8")
    print(summary[["accuracy", "macro_f1_test_present_classes", "weighted_f1", "binary_recall_attack", "binary_false_positive_rate", "count_wrong_attack_type"]].to_string())
    print(f"Comparison saved to {output}")


if __name__ == "__main__":
    main()
