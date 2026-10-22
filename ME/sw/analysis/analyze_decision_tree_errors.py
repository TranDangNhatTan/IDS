"""Audit saved binary predictions by original attack name without fitting a model."""

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from ME.sw.paths import RAW_DATA_DIR, TREE_DIR
from ME.sw.train_model.train_decision_tree import FEATURES, plt, sha256, write_json


def attach_predictions(raw, saved):
    ids = saved["source_row_zero_based"]
    if ids.duplicated().any() or set(ids) != set(range(len(raw))):
        raise ValueError("Saved prediction row IDs do not match the dataset exactly")
    saved = saved.set_index("source_row_zero_based").loc[raw.index]
    actual = raw["label"].str.strip().ne("normal").astype(int)
    if not np.array_equal(actual, saved.actual) or not saved.predicted.isin([0, 1]).all():
        raise ValueError("Saved binary labels do not match original labels")
    records = raw.copy()
    records.insert(0, "source_line_one_based", records.index + 1)
    records["actual_attack_type"] = records.pop("label").str.strip()
    records["predicted_binary"] = saved.predicted.map({0: "normal", 1: "attack"})
    records["outcome"] = np.select(
        [(actual == 0) & (saved.predicted == 0), (actual == 0) & (saved.predicted == 1),
         (actual == 1) & (saved.predicted == 0)], ["TN", "FP", "FN"], default="TP"
    )
    records["error_meaning"] = records.outcome.map({
        "TN": "normal được nhận đúng", "TP": "tấn công được phát hiện (chưa xác định tên)",
        "FP": "báo động nhầm: normal bị gọi là attack", "FN": "bỏ sót: tấn công bị gọi là normal",
    })
    return records


def summarize_types(records, train_counts):
    table = pd.crosstab(records.actual_attack_type, records.outcome).reindex(
        columns=["TN", "FP", "FN", "TP"], fill_value=0
    )
    table["test_count"] = table.sum(axis=1)
    table["train_count"] = table.index.map(lambda label: int(train_counts.get(label, 0)))
    table["seen_in_full_train"] = table.train_count.gt(0)
    table["binary_attack_detection_recall"] = np.where(
        table.index != "normal", table.TP / table.test_count, np.nan
    )
    table["normal_false_positive_rate"] = np.where(
        table.index == "normal", table.FP / table.test_count, np.nan
    )
    table["share_of_all_missed_attacks"] = table.FN / max(1, int(table.FN.sum()))
    return table.sort_values(["FN", "test_count"], ascending=False)


def markdown_table(frame):
    columns = list(frame.columns)
    lines = ["| " + " | ".join(map(str, columns)) + " |", "| " + " | ".join(["---"] * len(columns)) + " |"]
    for row in frame.itertuples(index=False, name=None):
        lines.append("| " + " | ".join(map(str, row)) + " |")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR)
    parser.add_argument("--run-dir", type=Path, default=TREE_DIR / "decision_tree")
    parser.add_argument("--output-dir", type=Path, default=TREE_DIR / "decision_tree" / "error_analysis")
    args = parser.parse_args()
    run = args.run_dir
    metadata = json.loads((run / "run_metadata.json").read_text(encoding="utf-8"))
    for filename, expected in metadata["sha256"].items():
        if sha256(args.data_dir / filename) != expected:
            raise ValueError(f"Dataset changed since original evaluation: {filename}")
    raw = pd.read_csv(args.data_dir / "KDDTest+.txt", header=None, names=FEATURES + ["label", "difficulty"])
    train_labels = pd.read_csv(args.data_dir / "KDDTrain+.txt", header=None, usecols=[41]).iloc[:, 0].str.strip()
    saved = pd.read_csv(run / "test_predictions.csv")
    records = attach_predictions(raw, saved)
    records["train_count_for_actual_type"] = records.actual_attack_type.map(train_labels.value_counts()).fillna(0).astype(int)
    summary = summarize_types(records, train_labels.value_counts())
    metrics = json.loads((run / "test_metrics.json").read_text(encoding="utf-8"))
    for code in ["TN", "FP", "FN", "TP"]:
        if int(records.outcome.eq(code).sum()) != metrics[code.lower()]:
            raise ValueError(f"Outcome totals disagree with original test metrics: {code}")

    # Traverse the unchanged tree only to explain errors; never fit or tune it.
    model = joblib.load(run / "decision_tree_pipeline.joblib")
    transformed = model.named_steps["preprocess"].transform(raw[FEATURES])
    tree = model.named_steps["model"]
    leaves = tree.apply(transformed)
    distributions = tree.tree_.value[leaves, 0, :]
    probabilities = distributions / distributions.sum(axis=1, keepdims=True)
    audit_predictions = tree.classes_[probabilities.argmax(axis=1)]
    aligned_predictions = saved.set_index("source_row_zero_based").loc[raw.index, "predicted"]
    np.testing.assert_array_equal(audit_predictions, aligned_predictions)
    records["leaf_id"] = leaves
    records["leaf_training_sample_count"] = tree.tree_.n_node_samples[leaves]
    records["leaf_attack_fraction_not_calibrated"] = probabilities[:, list(tree.classes_).index(1)]
    names = model.named_steps["preprocess"].get_feature_names_out()
    paths = tree.decision_path(transformed)
    errors = records.loc[records.outcome.isin(["FP", "FN"])].copy()
    explanations = []
    for index in errors.index:
        path = paths.indices[paths.indptr[index]:paths.indptr[index + 1]]
        rules = []
        for node in path:
            feature = tree.tree_.feature[node]
            if feature < 0:
                continue
            value = float(transformed[index, feature])
            threshold = float(tree.tree_.threshold[node])
            # sklearn's tree traversal converts inputs to float32.
            operator = "<=" if np.float32(value) <= threshold else ">"
            rules.append(f"{names[feature]} [value={value:.9g}] {operator} {threshold:.9g}")
        explanations.append(" AND ".join(rules))
    errors["learned_decision_path"] = explanations
    attacks = records.loc[records.actual_attack_type.ne("normal")].copy()
    attacks["type_seen_in_full_train"] = attacks.train_count_for_actual_type.gt(0)
    seen = attacks.groupby("type_seen_in_full_train").agg(
        test_attack_count=("outcome", "size"), detected=("outcome", lambda x: int(x.eq("TP").sum())),
        missed=("outcome", lambda x: int(x.eq("FN").sum())), type_count=("actual_attack_type", "nunique"),
    )
    seen["binary_attack_recall"] = seen.detected / seen.test_attack_count
    normals = records.loc[records.actual_attack_type.eq("normal")]
    fp_context = normals.groupby(["protocol_type", "service", "flag"]).agg(
        normal_count=("outcome", "size"), false_positives=("outcome", lambda x: int(x.eq("FP").sum()))
    )
    fp_context["false_positive_rate"] = fp_context.false_positives / fp_context.normal_count
    fp_context = fp_context.sort_values("false_positives", ascending=False)
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=False)
    records.to_csv(output / "all_predictions_with_attack_types.csv", index=False, encoding="utf-8-sig")
    errors.to_csv(output / "misclassified_records_with_paths.csv", index=False, encoding="utf-8-sig")
    summary.to_csv(output / "per_attack_type.csv", encoding="utf-8-sig")
    seen.to_csv(output / "seen_vs_unseen_attack_types.csv")
    fp_context.to_csv(output / "false_positives_by_context.csv")

    attack_summary = summary.drop(index="normal")
    figure, axis = plt.subplots(figsize=(10, 11))
    labels = [f"{name} (n={row.test_count})" for name, row in attack_summary.iterrows()]
    positions = np.arange(len(labels))
    axis.barh(positions, attack_summary.binary_attack_detection_recall * 100,
              color=["#2563eb" if seen_type else "#d97706" for seen_type in attack_summary.seen_in_full_train])
    axis.set_yticks(positions, labels, fontsize=8)
    axis.invert_yaxis()
    axis.set_xlim(0, 105)
    axis.set_xlabel("Binary attack detection recall (%) — not attack-name classification")
    axis.set_title("Detection by actual attack name\nBlue: label seen in training; orange: unseen label")
    axis.grid(axis="x", alpha=0.2)
    figure.tight_layout()
    figure.savefig(output / "recall_by_attack_type.png", dpi=160)
    plt.close(figure)

    display = attack_summary[["train_count", "test_count", "TP", "FN", "binary_attack_detection_recall"]].reset_index()
    display.columns = ["Nhãn thật", "Số mẫu train", "Số mẫu test", "Phát hiện attack", "Bỏ sót", "Recall phát hiện"]
    display["Recall phát hiện"] = display["Recall phát hiện"].map(lambda value: f"{value:.2%}")
    report = [
        "# Đánh giá lại Decision Tree theo từng loại tấn công", "",
        "Phân tích lại dự đoán đã lưu của model cố định; không train lại, không đổi ngưỡng và không chọn model theo test. Checksum dữ liệu và tổng confusion matrix đã được đối chiếu.", "",
        "## Model thực sự làm gì?", "",
        f"Model là `{type(tree).__name__}`, max_depth={tree.max_depth}, không phải Random Forest. Cây học các phép chia đặc trưng từ dữ liệu train bằng tiêu chí Gini. Script không đặt một ngưỡng cảnh báo thủ công sau dự đoán. `predict` chọn lớp có tỷ lệ cao nhất tại lá (hòa chọn lớp đầu trong classes_).", "",
        "Nhãn train đã gộp thành normal/attack nên model chỉ học hai lớp này. Tên tấn công trong báo cáo lấy từ nhãn thật của KDDTest+, không phải tên model tự dự đoán. Thay cây bằng Random Forest nhưng vẫn giữ nhãn nhị phân cũng không tạo được đầu ra tên tấn công.", "",
        "## Ý nghĩa từng chỉ số và lỗi", "",
        f"- TN = {metrics['tn']}: normal được nhận đúng.",
        f"- FP = {metrics['fp']}: normal bị báo nhầm là attack.",
        f"- FN = {metrics['fn']}: tấn công bị bỏ sót, dự đoán thành normal.",
        f"- TP = {metrics['tp']}: phát hiện có tấn công; chưa xác định đúng tên loại tấn công.",
        f"- Precision attack = {metrics['precision_attack']:.2%}: tỷ lệ cảnh báo attack là tấn công thật.",
        f"- Recall attack = {metrics['recall_attack']:.2%}: tỷ lệ tấn công thật được phát hiện; bỏ sót {1-metrics['recall_attack']:.2%}.",
        f"- F1 attack = {metrics['f1_attack']:.2%}: trung bình điều hòa precision và recall của lớp attack.",
        f"- FPR = {metrics['false_positive_rate']:.2%}: tỷ lệ mẫu normal bị báo nhầm; mẫu số là toàn bộ normal.",
        f"- Accuracy = {metrics['accuracy']:.2%}: tỷ lệ dự đoán nhị phân đúng trên tất cả mẫu; không thể hiện mức độ nhận diện từng loại tấn công.", "",
        "## Từng nhãn tấn công gốc", "",
        "Recall dưới đây = số mẫu của loại đó được báo attack / số mẫu test của loại đó. Không phải recall nhận dạng đúng tên loại. Không báo precision/F1 cho từng tên vì model không có dự đoán tên lớp tương ứng. Các loại chỉ có vài mẫu không cho bằng chứng mạnh về khả năng tổng quát hóa.", "",
        *markdown_table(display), "", "![Recall theo loại](recall_by_attack_type.png)", "",
        "## Nhãn từng thấy / chưa từng thấy trong toàn bộ KDDTrain+", "",
        *markdown_table(seen.reset_index()), "",
        "Seen/unseen ở đây chỉ nói về tên nhãn gốc, không chứng minh nguyên nhân gây lỗi. Cây nhị phân vẫn có thể phát hiện tấn công mang nhãn chưa gặp, nhưng không thể tự đặt tên cho lớp chưa được học.", "",
        "## Tra cứu từng mẫu sai", "",
        "Mở `misclassified_records_with_paths.csv`: `source_line_one_based` là số dòng trong KDDTest+.txt; `actual_attack_type` là loại tấn công thật; `predicted_binary` là dự đoán; `outcome` phân biệt FN/FP; `error_meaning` giải thích lỗi. CSV giữ 41 đặc trưng và đường đi `learned_decision_path` qua các ngưỡng cây đã học.", "",
        "`leaf_attack_fraction_not_calibrated` là tỷ lệ attack tại lá trong dữ liệu fit, không phải xác suất được hiệu chỉnh hay bằng chứng mẫu an toàn. Đường đi giải thích cơ chế quyết định, không chứng minh nguyên nhân thực tế của tấn công. One-hot có giá trị 0/1; ngưỡng 0.5 kiểm tra category có/không.", "",
        "`false_positives_by_context.csv` gom mẫu normal theo protocol/service/flag kèm số mẫu và FPR; không kết luận các đặc trưng đó là nguyên nhân lỗi chỉ từ bảng thống kê.", "",
        "## Kết luận và yêu cầu đầu ra", "",
        "Baseline có giá trị đo khả năng phát hiện có tấn công, nhưng chưa đáp ứng yêu cầu xác định loại tấn công. Precision cao không bù được số lượng lớn tấn công bị bỏ sót. Chênh lệch validation/test cho thấy khả năng tổng quát hóa trên test yếu hơn; riêng chênh lệch này chưa đủ kết luận nguyên nhân duy nhất là overfit.", "",
        "Nếu đầu ra cần tên tấn công, phải giữ nhãn đa lớp khi train (Decision Tree hoặc Random Forest), đánh giá confusion matrix đa lớp và precision/recall/F1/support từng lớp, macro-F1 và weighted-F1. Nhãn chỉ xuất hiện trong test phải báo riêng; model phân loại đóng không thể học tên lớp chưa có trong train. Nếu thay thiết kế dựa trên phân tích test này, KDDTest+ là dữ liệu phát triển/benchmark đã xem, không còn là tập đánh giá độc lập cho phiên bản mới.", "",
    ]
    (output / "report_vi.md").write_text("\n".join(report), encoding="utf-8")
    write_json(output / "audit.json", {
        "source_run": str(run.resolve()), "model_type": type(tree).__name__,
        "saved_predictions_sha256": sha256(run / "test_predictions.csv"),
        "model_sha256": sha256(run / "decision_tree_pipeline.joblib"),
        "fit_performed": False, "threshold_changed": False,
        "dataset_hashes_match": True, "saved_predictions_match_tree_paths": True,
        "misclassified_count": len(errors), "attack_types_in_test": len(attack_summary),
    })
    print(attack_summary[["train_count", "test_count", "TP", "FN", "binary_attack_detection_recall"]].to_string())
    print("\nSeen/unseen types:\n" + seen.to_string())
    print(f"\nSaved {len(errors)} errors and report to {output}")


if __name__ == "__main__":
    main()
