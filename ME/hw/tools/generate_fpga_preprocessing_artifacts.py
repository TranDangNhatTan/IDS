"""Export a fixed-point preprocessing and tree contract for the trained Decision Tree."""

import argparse
import json
import math
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from ME.sw.paths import GROUND_TRUTH_DIR, GROUND_TRUTH_MODEL_DIR, HW_EXPORT_DIR
from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, NUMERIC, write_json


BASIC = {"duration", "protocol_type", "service", "flag", "src_bytes", "dst_bytes", "land", "wrong_fragment", "urgent"}
CONTENT = {"hot", "num_failed_logins", "logged_in", "num_compromised", "root_shell", "su_attempted", "num_root", "num_file_creations", "num_shells", "num_access_files", "num_outbound_cmds", "is_host_login", "is_guest_login"}
TIME = {"count", "srv_count", "serror_rate", "srv_serror_rate", "rerror_rate", "srv_rerror_rate", "same_srv_rate", "diff_srv_rate", "srv_diff_host_rate"}
HOST = set(NUMERIC) - BASIC - CONTENT - TIME
RATES = {"serror_rate", "srv_serror_rate", "rerror_rate", "srv_rerror_rate", "same_srv_rate", "diff_srv_rate", "srv_diff_host_rate", "dst_host_same_srv_rate", "dst_host_diff_srv_rate", "dst_host_same_src_port_rate", "dst_host_srv_diff_host_rate", "dst_host_serror_rate", "dst_host_srv_serror_rate", "dst_host_rerror_rate", "dst_host_srv_rerror_rate"}
RATE_SCALE = 65535


def bits_for(maximum):
    return max(1, math.ceil(math.log2(int(maximum) + 1)))


def source_for(feature):
    if feature in BASIC:
        return "L2/L3/L4 parser + per-flow counters"
    if feature in CONTENT:
        return "Payload/L7 parser or host telemetry; unavailable from headers alone"
    if feature in TIME:
        return "Time-window flow table"
    return "Destination-host history table"


def group_for(feature):
    if feature in BASIC:
        return "basic"
    if feature in CONTENT:
        return "content"
    if feature in TIME:
        return "time_window"
    return "host_window"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ground-truth", type=Path, default=GROUND_TRUTH_DIR / "ground_truth_nsl_kdd.csv")
    parser.add_argument("--model-dir", type=Path, default=GROUND_TRUTH_MODEL_DIR)
    parser.add_argument("--output-dir", type=Path, default=HW_EXPORT_DIR)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    data = pd.read_csv(args.ground_truth)
    model = joblib.load(args.model_dir / "pipeline.joblib")
    preprocessing = model.named_steps["preprocess"]
    tree = model.named_steps["model"]
    encoder = preprocessing.named_transformers_["categorical"]
    encoded_names = preprocessing.get_feature_names_out()
    name_to_index = {name: index for index, name in enumerate(encoded_names)}
    used_encoded = set(tree.tree_.feature[tree.tree_.feature >= 0])
    numeric_nodes = {}
    for feature in NUMERIC:
        encoded_index = name_to_index[f"numeric__{feature}"]
        numeric_nodes[feature] = tree.tree_.threshold[tree.tree_.feature == encoded_index]
    category_codes = {}
    category_rows = []
    for column, values in zip(CATEGORICAL, encoder.categories_):
        category_codes[column] = {str(value): code for code, value in enumerate(values, start=1)}
        for value, code in category_codes[column].items():
            category_rows.append({"raw_feature": column, "category": value, "code": code})
    pd.DataFrame(category_rows).to_csv(output / "fpga_category_codes.csv", index=False)

    input_rows = []
    for feature in FEATURES:
        if feature in CATEGORICAL:
            categories = category_codes[feature]
            width = bits_for(max(categories.values()))
            input_rows.append({"raw_feature": feature, "group": group_for(feature), "source": source_for(feature),
                               "observed_min": "", "observed_max": "", "used_by_tree": True,
                               "representation": f"UINT{width} category code; 0=unknown", "bit_width": width,
                               "scale": 1, "saturate_at": max(categories.values()), "notes": "See fpga_category_codes.csv; unknown behaves as all-zero one-hot."})
            continue
        observed_max = int(data[feature].max()) if feature not in RATES else 1.0
        thresholds = numeric_nodes[feature]
        used = len(thresholds) > 0
        if feature in RATES:
            representation, width, scale, saturation = "UINT16 normalized rate Q0.16", 16, RATE_SCALE, 1.0
            note = "code = round(clamp(rate,0,1) * 65535)"
        elif used:
            saturation = int(math.floor(float(thresholds.max()))) + 1
            width, scale = bits_for(saturation), 1
            representation = f"UINT{width} saturating integer"
            note = "Values above saturation are equivalent for this trained tree."
        else:
            saturation, width, scale = "not exported", 0, 1
            representation, note = "not needed by current tree", "num_outbound_cmds is unused by every decision node."
        input_rows.append({"raw_feature": feature, "group": group_for(feature), "source": source_for(feature),
                           "observed_min": data[feature].min(), "observed_max": observed_max, "used_by_tree": used,
                           "representation": representation, "bit_width": width, "scale": scale,
                           "saturate_at": saturation, "notes": note})
    inputs = pd.DataFrame(input_rows)
    inputs.to_csv(output / "fpga_input_schema.csv", index=False)

    encoded_category_lookup = {}
    for column, values in category_codes.items():
        for category, code in values.items():
            encoded_category_lookup[name_to_index[f"categorical__{column}_{category}"]] = (column, code)
    fpga_nodes = []
    for node in range(tree.tree_.node_count):
        encoded_index = int(tree.tree_.feature[node])
        base = {"node_id": node, "left_child": int(tree.tree_.children_left[node]), "right_child": int(tree.tree_.children_right[node]),
                "sample_count": int(tree.tree_.n_node_samples[node]), "predicted_class": str(tree.classes_[tree.tree_.value[node, 0].argmax()])}
        if encoded_index < 0:
            fpga_nodes.append({**base, "operation": "LEAF", "raw_feature": "", "bit_width": 0, "operand": "", "true_child": "", "false_child": ""})
        elif encoded_index in encoded_category_lookup:
            feature, category_code = encoded_category_lookup[encoded_index]
            # sklearn left = one-hot <= 0.5 (not equal); right = equal.
            fpga_nodes.append({**base, "operation": "CATEGORY_EQ", "raw_feature": feature,
                               "bit_width": int(inputs.loc[inputs.raw_feature.eq(feature), "bit_width"].iloc[0]),
                               "operand": category_code, "true_child": int(tree.tree_.children_right[node]),
                               "false_child": int(tree.tree_.children_left[node])})
        else:
            raw_feature = encoded_names[encoded_index].replace("numeric__", "")
            if raw_feature in RATES:
                operand = int(round(float(tree.tree_.threshold[node]) * RATE_SCALE))
            else:
                operand = int(math.floor(float(tree.tree_.threshold[node])))
            # Condition is raw_code <= operand; sklearn left is true.
            fpga_nodes.append({**base, "operation": "NUMERIC_LE", "raw_feature": raw_feature,
                               "bit_width": int(inputs.loc[inputs.raw_feature.eq(raw_feature), "bit_width"].iloc[0]),
                               "operand": operand, "true_child": int(tree.tree_.children_left[node]),
                               "false_child": int(tree.tree_.children_right[node])})
    exported = pd.DataFrame(fpga_nodes)
    exported.to_csv(output / "fpga_tree_nodes.csv", index=False)

    # Vectorized parity check: generated fixed-point/category decisions must
    # select the same leaves as sklearn for every clean ground-truth row.
    count = len(data)
    current = np.zeros(count, dtype=np.int32)
    leaf = tree.tree_.children_left == -1
    integer_codes = {}
    for feature in NUMERIC:
        values = data[feature].to_numpy()
        if feature in RATES:
            integer_codes[feature] = np.rint(np.clip(values, 0, 1) * RATE_SCALE).astype(np.int64)
        else:
            row = inputs.loc[inputs.raw_feature.eq(feature)].iloc[0]
            if int(row.bit_width) > 0:
                integer_codes[feature] = np.minimum(values.astype(np.int64), int(row.saturate_at))
    categorical_codes = {feature: data[feature].map(category_codes[feature]).fillna(0).astype(np.int64).to_numpy() for feature in CATEGORICAL}
    while not np.all(leaf[current]):
        for node in np.unique(current[~leaf[current]]):
            indices = np.flatnonzero(current == node)
            record = exported.iloc[node]
            if record.operation == "CATEGORY_EQ":
                condition = categorical_codes[record.raw_feature][indices] == int(record.operand)
            else:
                condition = integer_codes[record.raw_feature][indices] <= int(record.operand)
            current[indices[condition]] = int(record.true_child)
            current[indices[~condition]] = int(record.false_child)
    fpga_labels = tree.classes_[tree.tree_.value[current, 0].argmax(axis=1)]
    sklearn_labels = model.predict(data[FEATURES])
    parity = bool(np.array_equal(fpga_labels, sklearn_labels))
    if not parity:
        raise AssertionError(f"Fixed-point export differs on {np.count_nonzero(fpga_labels != sklearn_labels)} ground-truth rows")
    summary = {"raw_input_features": len(FEATURES), "encoded_sklearn_features": len(encoded_names),
               "features_used_by_tree": int(inputs.used_by_tree.sum()), "tree_nodes": int(tree.tree_.node_count),
               "leaf_nodes": int((exported.operation == "LEAF").sum()), "rate_scale": RATE_SCALE,
               "parity_checked_rows": count, "fixed_point_tree_matches_sklearn": parity,
               "header_or_flow_only_features_used": int(inputs.loc[inputs.group.ne("content") & inputs.used_by_tree, "used_by_tree"].sum()),
               "content_features_used": inputs.loc[inputs.group.eq("content") & inputs.used_by_tree, "raw_feature"].tolist()}
    write_json(output / "fpga_export_summary.json", summary)
    spec = [
        "# Đặc tả tiền xử lý FPGA — Decision Tree ground truth", "",
        "Đặc tả này xuất trực tiếp từ `pipeline.joblib`. `fpga_tree_nodes.csv` không cần tạo 121 one-hot bit: node category được chuyển thành so sánh mã category. Parity check đã kiểm tra toàn bộ ground truth sạch và cho cùng nhãn với sklearn.", "",
        "## Đồng bộ và luồng dữ liệu", "",
        "1. RX MAC tạo stream packet trong clock domain RX: `data`, `valid`, `ready`, `last`, `timestamp`.",
        "2. Nếu RX clock khác clock xử lý, qua asynchronous FIFO; không đưa state flow qua CDC từng bit. Descriptor hoặc record chỉ được đọc ở system clock sau FIFO.",
        "3. Parser Ethernet/IPv4/L4 tạo flow key `(src_ip, dst_ip, src_port, dst_port, protocol)`. Với ICMP, thay port bằng type/code hoặc 0 theo quy ước cố định.",
        "4. Flow-table update phải serialize read-modify-write theo flow key hoặc có hazard detector. Hai packet cùng flow không được cập nhật counter song song mất dữ liệu.",
        "5. Khi FIN/RST hoặc timeout, đóng flow, chốt feature, giữ record stable cùng `feature_valid=1`, rồi đưa vào evaluator. Các counter và rate code phải stable đến khi `result_valid` được nhận.",
        "6. Timeout/counter cần saturate theo fpga_input_schema.csv; overflow không được wrap. Feature thiếu phải có `feature_valid=0` và trả `unknown`, không thay bằng 0.", "",
        "## Kiểu dữ liệu", "",
        "- Categorical: protocol UINT2, service UINT7, flag UINT4. Code 0 là unknown; tại node category nó luôn đi nhánh not-equal, giống `OneHotEncoder(handle_unknown='ignore')`.",
        "- Rate: UINT16 Q0.16. Mã hóa `round(clamp(numerator/denominator,0,1) * 65535)`. Cả feature và ngưỡng phải dùng cùng scale 65535.",
        "- Integer: unsigned, saturating. Chiều rộng chính xác theo fpga_input_schema.csv. Không dùng float trong RTL.",
        "- Duration: đơn vị phải thống nhất với train là giây nguyên. Nếu timestamp FPGA theo tick, dùng `duration = floor((end_tick-start_tick)/ticks_per_second)` trước khi đưa vào cây.", "",
        "## Hạn chế quan trọng", "",
        "Cây hiện tại dùng feature content: " + ", ".join(summary["content_features_used"]) + ". Các feature này yêu cầu payload/L7 parser hoặc telemetry host; header IPv4/TCP/UDP thuần không thể tạo tương đương. Không được gán 0 nếu muốn giữ độ chính xác model hiện tại. Nếu FPGA chỉ parse header/flow, phải train một cây mới chỉ với feature basic/time_window/host_window khả thi.", "",
        "Các file liên quan: `fpga_input_schema.csv` (interface), `fpga_category_codes.csv` (enum), `fpga_tree_nodes.csv` (tree đã chuyển category/fixed-point), `feature_schema.json` (schema sklearn gốc).", "",
    ]
    (output / "fpga_preprocessing_spec.md").write_text("\n".join(spec), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
