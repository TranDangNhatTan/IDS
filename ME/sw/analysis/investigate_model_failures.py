"""Diagnose saved multiclass runs without fitting or changing either model."""

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from scipy.stats import ks_2samp
from sklearn.metrics import classification_report, confusion_matrix

from ME.sw.paths import RAW_DATA_DIR, TREE_DIR
from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, NUMERIC, sha256, write_json


FAMILIES = {
    "normal": "normal",
    **{x: "DoS" for x in "apache2 back land mailbomb neptune pod processtable smurf teardrop udpstorm worm".split()},
    **{x: "Probe" for x in "ipsweep mscan nmap portsweep saint satan".split()},
    **{x: "R2L" for x in "ftp_write guess_passwd httptunnel imap multihop named phf sendmail snmpgetattack snmpguess spy warezclient warezmaster xlock xsnoop".split()},
    **{x: "U2R" for x in "buffer_overflow loadmodule perl ps rootkit sqlattack xterm".split()},
}


def family(label):
    if label not in FAMILIES:
        raise ValueError(f"Missing attack-family mapping: {label}")
    return FAMILIES[label]


def main():
    output = TREE_DIR / "failure_investigation"
    output.mkdir(parents=True, exist_ok=True)
    columns = FEATURES + ["label", "difficulty"]
    train = pd.read_csv(RAW_DATA_DIR / "KDDTrain+.txt", header=None, names=columns)
    test = pd.read_csv(RAW_DATA_DIR / "KDDTest+.txt", header=None, names=columns)
    train_labels, test_labels = set(train.label), set(test.label)
    union = train_labels | test_labels
    if set(FAMILIES) != union:
        raise ValueError(f"Family mapping mismatch; missing={union-set(FAMILIES)}, extra={set(FAMILIES)-union}")

    category_rows = []
    for column in CATEGORICAL:
        train_values, test_values = set(train[column]), set(test[column])
        category_rows.append({"feature": column, "train_unique": len(train_values), "test_unique": len(test_values),
                              "test_only_values": ", ".join(sorted(test_values-train_values)),
                              "affected_test_rows": int(test[column].isin(test_values-train_values).sum())})
    pd.DataFrame(category_rows).to_csv(output / "categorical_coverage.csv", index=False)

    support = pd.DataFrame({"train_support": train.label.value_counts(), "test_support": test.label.value_counts()}).fillna(0).astype(int)
    support["seen_in_train"] = support.train_support.gt(0)
    support["test_per_train"] = support.test_support / support.train_support.replace(0, np.nan)
    support.to_csv(output / "label_distribution_shift.csv", index_label="attack_type")

    drift_rows = []
    for label in ["guess_passwd", "warezmaster"]:
        left, right = train.loc[train.label.eq(label)], test.loc[test.label.eq(label)]
        for feature in NUMERIC:
            statistic, pvalue = ks_2samp(left[feature], right[feature])
            drift_rows.append({"attack_type": label, "feature": feature, "ks_statistic": statistic,
                               "p_value_descriptive_only": pvalue,
                               "train_median": left[feature].median(), "test_median": right[feature].median()})
    drift = pd.DataFrame(drift_rows).sort_values(["attack_type", "ks_statistic"], ascending=[True, False])
    drift.to_csv(output / "feature_shift_guess_passwd_warezmaster.csv", index=False)

    model_rows, confidence_rows = [], []
    for model_name in ["decision_tree_multiclass", "random_forest_multiclass"]:
        run = TREE_DIR / model_name
        metadata = json.loads((run / "run_metadata.json").read_text(encoding="utf-8"))
        for filename, expected in metadata["sha256"].items():
            if sha256(RAW_DATA_DIR / filename) != expected:
                raise ValueError(f"Dataset changed: {filename}")
        saved = pd.read_csv(run / "test_predictions.csv")
        if not np.array_equal(saved.actual_type, test.label):
            raise ValueError(f"Prediction rows misaligned: {model_name}")
        actual_family = saved.actual_type.map(family)
        predicted_family = saved.predicted_type.map(family)
        family_labels = ["normal", "DoS", "Probe", "R2L", "U2R"]
        report = classification_report(actual_family, predicted_family, labels=family_labels, output_dict=True, zero_division=0)
        family_table = pd.DataFrame({label: report[label] for label in family_labels}).T
        family_table.to_csv(output / f"{model_name}_family_metrics.csv", index_label="family")
        pd.DataFrame(confusion_matrix(actual_family, predicted_family, labels=family_labels),
                     index=family_labels, columns=family_labels).to_csv(output / f"{model_name}_family_confusion.csv", index_label="actual_family")
        model_rows.append({"model": model_name, "family_accuracy": report["accuracy"],
                           "family_macro_f1": report["macro avg"]["f1-score"],
                           "family_weighted_f1": report["weighted avg"]["f1-score"],
                           **{f"{label}_recall": report[label]["recall"] for label in family_labels},
                           "tree_count": metadata["tree_count"], "total_nodes": metadata["total_nodes"],
                           "model_file_bytes": metadata["model_file_bytes"],
                           "test_predict_seconds": metadata["test_predict_seconds"]})

        model = joblib.load(run / "pipeline.joblib")
        probability = model.predict_proba(test[FEATURES])
        predicted = model.classes_[probability.argmax(axis=1)]
        np.testing.assert_array_equal(predicted, saved.predicted_type)
        maximum = probability.max(axis=1)
        normal_probability = probability[:, list(model.classes_).index("normal")]
        outcome = saved.error_type.to_numpy()
        for kind in sorted(set(outcome)):
            values = maximum[outcome == kind]
            confidence_rows.append({"model": model_name, "outcome": kind, "count": len(values),
                                    "mean_max_class_probability": values.mean(), "median": np.median(values),
                                    "p10": np.quantile(values, .1), "p90": np.quantile(values, .9)})
        missed = (saved.actual_type != "normal") & (saved.predicted_type == "normal")
        model_rows[-1]["missed_attacks"] = int(missed.sum())
        model_rows[-1]["missed_with_normal_probability_below_0_5"] = int((normal_probability[missed] < .5).sum())
        model_rows[-1]["fraction_missed_below_0_5"] = float((normal_probability[missed] < .5).mean())
    comparison = pd.DataFrame(model_rows).set_index("model")
    comparison.to_csv(output / "family_and_complexity_comparison.csv")
    pd.DataFrame(confidence_rows).to_csv(output / "confidence_by_error.csv", index=False)

    top_shift = drift.groupby("attack_type").head(5)
    report = [
        "# Điều tra nguyên nhân nhầm lẫn và bỏ sót", "",
        "Phân tích này đọc hai model và dự đoán đã lưu; không fit lại, không đổi ngưỡng và không chọn cấu hình dựa trên KDDTest+. Vì KDDTest+ đã được xem, các phát hiện là chẩn đoán benchmark, không phải bằng chứng trên holdout mới.", "",
        "## Kết luận nguyên nhân", "",
        f"1. **Open-set / nhãn chưa học:** train có {len(train_labels)} tên lớp, test có {len(test_labels)}, giao nhau {len(train_labels & test_labels)}. Có {len(test_labels-train_labels)} nhãn chỉ xuất hiện trong test ({int(test.label.isin(test_labels-train_labels).sum())} mẫu). Classifier đóng không thể xuất đúng một tên chưa có trong classes_.",
        "2. **Mất cân bằng và support quá nhỏ:** nhiều lớp chỉ có 2–53 mẫu train. `guess_passwd` có 53 train nhưng 1.231 test; `warezmaster` có 20 train nhưng 944 test. Một hoặc vài mẫu validation ở lớp hiếm làm macro-F1 lựa chọn model dao động mạnh.",
        "3. **Concept/covariate shift:** cùng một tên lớp có phân bố đặc trưng khác giữa train và test. File feature_shift ghi KS statistic; đây là bằng chứng về khác biệt phân bố, không tự chứng minh nguyên nhân vật lý.",
        "4. **Mục tiêu đa lớp trực tiếp gây bỏ sót:** `predict` chọn lớp có xác suất lớn nhất. Với Random Forest, normal có thể là lớp đơn lớn nhất dù tổng xác suất các lớp attack lớn hơn. 3.134/4.805 mẫu attack bị RF gọi normal có P(normal) < 0,5. Vì vậy nên tách cổng normal/attack khỏi bước đặt tên.",
        "5. **Decision Tree quá tự tin:** cây không giới hạn tạo lá gần thuần, cho xác suất 1,0 cả với nhiều lỗi. Xác suất lá này không được hiệu chỉnh và không nên xem là độ tin cậy thực.",
        "6. **Không phải lỗi category chưa biết:** protocol/service/flag trong test đều thuộc tập category đã có trong train. `handle_unknown=ignore` không phải nguyên nhân chính của benchmark này.", "",
        "## Kết quả theo họ tấn công", "",
        "Gộp tên về normal/DoS/Probe/R2L/U2R giúp đo mức hữu ích khi tên cụ thể chưa có trong train. Đây là phép đánh giá bổ sung, không thay đổi model.", "",
        "| Model | Family accuracy | Family macro-F1 | DoS recall | Probe recall | R2L recall | U2R recall |", "|---|---:|---:|---:|---:|---:|---:|",
        *[f"| {name} | {row.family_accuracy:.2%} | {row.family_macro_f1:.2%} | {row.DoS_recall:.2%} | {row.Probe_recall:.2%} | {row.R2L_recall:.2%} | {row.U2R_recall:.2%} |" for name, row in comparison.iterrows()], "",
        "## Dấu hiệu lệch đặc trưng mạnh nhất", "",
        "| Loại | Feature | KS | Median train | Median test |", "|---|---|---:|---:|---:|",
        *[f"| {row.attack_type} | {row.feature} | {row.ks_statistic:.3f} | {row.train_median:.4g} | {row.test_median:.4g} |" for row in top_shift.itertuples(index=False)], "",
        "KS gần 1 nghĩa phân bố thực nghiệm rất khác. P-value chỉ được lưu để tham khảo; với nhiều phép thử và dữ liệu lệch lớp, không dùng nó làm tiêu chí chọn model.", "",
        "## Chọn thuật toán", "",
        "Nếu mục tiêu ưu tiên FPGA và không bỏ sót, **Decision Tree hiện hợp lý hơn trong hai model đã chạy**: recall attack 67,66% so với RF 62,56%, model 1 cây/1.003 node/0,26 MB so với 200 cây/112.536 node/28,03 MB. RF có macro-F1 theo tên tốt hơn (26,88% so với 24,87%) và ít báo động nhầm hơn một chút, nhưng chi phí lớn hơn nhiều và bỏ sót thêm 655 attack.", "",
        "Thiết kế hợp lý nhất là **phân cấp hai tầng**, thay vì một classifier đa lớp trực tiếp:", "",
        "1. Tầng 1: binary normal/attack, chọn threshold trên validation theo chi phí FN cao hơn FP; báo cả score. Đây là tầng triển khai FPGA.",
        "2. Tầng 2: chỉ chạy trên mẫu đã được tầng 1 báo attack; phân loại DoS/Probe/R2L/U2R trước, sau đó mới đặt tên cụ thể nếu đủ dữ liệu.",
        "3. Nếu score hoặc khoảng cách phân bố không đủ chắc, trả `unknown_attack`; không ép về normal hay một tên đã biết.", "",
        "Có thể dùng Decision Tree/pruned small forest cho tầng 1 trên FPGA; nếu có CPU/MCU phía sau, dùng Random Forest nhỏ hoặc gradient-boosted trees cho tầng đặt tên. Nếu tất cả phải ở FPGA, thử ensemble 8–32 cây nông và so sánh Pareto recall/FPR/node count; RF 200 cây hiện tại quá lớn so với lợi ích đo được.", "",
        "## Thứ tự cải tiến nên thực hiện", "",
        "- Đổi mục tiêu chọn tầng 1 sang recall attack với ràng buộc FPR, ví dụ tối đa FPR cho phép rồi chọn recall cao nhất. Chọn threshold bằng out-of-fold validation, không dùng test.",
        "- Dùng repeated stratified cross-validation cho lớp đủ mẫu; với lớp 2–10 mẫu, cần thu thập thêm hoặc gộp theo family. Không thể sửa thiếu dữ liệu chỉ bằng class_weight/SMOTE.",
        "- Huấn luyện family classifier và unknown detector. Đánh giá riêng known/unknown, confusion family và false-negative rate.",
        "- Thử `min_samples_leaf`, pruning `ccp_alpha`, class/cost weights và cây nông; báo đường Pareto giữa recall, FPR, macro-F1, node count và dung lượng.",
        "- Với RF, giảm còn 8/16/32/64 cây, tune `max_depth`, `min_samples_leaf`, `max_features`; hiệu chỉnh xác suất bằng validation trước khi đặt threshold.",
        "- Không random oversample trước split. Nếu dùng sampling/SMOTE, chỉ áp dụng bên trong từng fold train và ưu tiên dữ liệu thật cho R2L/U2R hiếm.",
        "- Tạo holdout mới hoặc dùng dataset khác sau khi chốt pipeline, vì KDDTest+ đã tham gia phân tích.", "",
        "Các file CSV trong thư mục này chứa family confusion matrix, độ tin cậy theo loại lỗi, coverage category, support shift và feature shift.", "",
    ]
    (output / "report_vi.md").write_text("\n".join(report), encoding="utf-8")
    write_json(output / "audit.json", {"fit_performed": False, "threshold_changed": False,
        "models": ["decision_tree_multiclass", "random_forest_multiclass"],
        "train_class_count": len(train_labels), "test_class_count": len(test_labels),
        "test_only_classes": sorted(test_labels-train_labels),
        "test_only_sample_count": int(test.label.isin(test_labels-train_labels).sum())})
    print(comparison.to_string())
    print(f"\nReport saved to {output / 'report_vi.md'}")


if __name__ == "__main__":
    main()
