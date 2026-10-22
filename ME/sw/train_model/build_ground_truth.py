"""Build a clean project-specific NSL-KDD ground truth from the two full files."""

import argparse
import csv
import json
from pathlib import Path

import pandas as pd

from ME.sw.paths import GROUND_TRUTH_DIR, RAW_DATA_DIR
from ME.sw.train_model.train_decision_tree import FEATURES, sha256, write_json


SOURCE_FILES = ["KDDTrain+.txt", "KDDTest+.txt"]
SUBSET_FILES = {"KDDTrain+_20Percent.txt": "KDDTrain+.txt", "KDDTest-21.txt": "KDDTest+.txt"}
COLUMNS = FEATURES + ["label", "difficulty"]


def inspect_file(path):
    counts = {}
    rows = 0
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle):
            rows += 1
            counts[len(row)] = counts.get(len(row), 0) + 1
    if counts != {43: rows}:
        raise ValueError(f"{path}: expected exactly 43 fields per row, got {counts}")
    return {"rows": rows, "field_count_distribution": counts, "sha256": sha256(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=GROUND_TRUTH_DIR)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ground_truth_path = output / "ground_truth_nsl_kdd.csv"
    if ground_truth_path.exists():
        raise FileExistsError(f"Refusing to overwrite existing ground truth: {ground_truth_path}")

    inspections = {name: inspect_file(args.data_dir / name) for name in SOURCE_FILES + list(SUBSET_FILES)}
    frames = []
    for filename in SOURCE_FILES:
        frame = pd.read_csv(args.data_dir / filename, header=None, names=COLUMNS)
        frame["label"] = frame.label.str.strip()
        frame["source_file"] = filename
        frame["source_row_one_based"] = range(1, len(frame) + 1)
        frames.append(frame)
    combined = pd.concat(frames, ignore_index=True)

    # Verify that named subset files add no new records. Adding them would only
    # duplicate observations and bias the randomly split ground truth.
    subset_checks = {}
    full_rows = {}
    for filename in SOURCE_FILES:
        full_rows[filename] = set(map(tuple, pd.read_csv(args.data_dir / filename, header=None).to_numpy()))
    for subset_name, full_name in SUBSET_FILES.items():
        subset_rows = set(map(tuple, pd.read_csv(args.data_dir / subset_name, header=None).to_numpy()))
        subset_checks[subset_name] = {"parent": full_name, "is_exact_subset": subset_rows <= full_rows[full_name],
                                      "unique_rows": len(subset_rows), "new_rows": len(subset_rows-full_rows[full_name])}
        if not subset_checks[subset_name]["is_exact_subset"]:
            raise ValueError(f"{subset_name} is not a subset of {full_name}")

    label_counts = combined.groupby(FEATURES, dropna=False).label.nunique()
    conflict_keys = label_counts[label_counts > 1].reset_index()[FEATURES]
    marked = combined.merge(conflict_keys.assign(label_conflict=True), on=FEATURES, how="left")
    conflict_mask = marked.label_conflict.eq(True)
    conflicts = marked.loc[conflict_mask].drop(columns="label_conflict")
    conflicts.sort_values(FEATURES + ["label"]).to_csv(output / "quarantined_label_conflicts.csv", index=False, encoding="utf-8-sig")

    consistent = marked.loc[~conflict_mask].drop(columns="label_conflict")
    duplicate_mask = consistent.duplicated(FEATURES, keep=False)
    consistent.loc[duplicate_mask].sort_values(FEATURES).to_csv(
        output / "deduplicated_consistent_records.csv", index=False, encoding="utf-8-sig"
    )
    # One unique input vector, one target. Difficulty/source are provenance only
    # and intentionally excluded from the model-ready ground truth.
    ground_truth = consistent.drop_duplicates(FEATURES, keep="first")[FEATURES + ["label"]]
    ground_truth.to_csv(ground_truth_path, index=False, encoding="utf-8")
    ground_truth.label.value_counts().sort_index().rename("count").to_csv(output / "class_counts.csv", index_label="attack_type")

    manifest = {
        "purpose": "Project-specific merged ground truth; not the standard NSL-KDD train/test benchmark",
        "input_files": inspections, "included_full_files": SOURCE_FILES,
        "excluded_subset_files": subset_checks,
        "raw_included_rows": len(combined),
        "exact_43_field_unique_rows": int(combined[COLUMNS].drop_duplicates().shape[0]),
        "unique_feature_vectors_before_conflict_removal": int(label_counts.size),
        "conflicting_feature_vectors": int(len(conflict_keys)),
        "raw_rows_quarantined_for_label_conflict": int(len(conflicts)),
        "clean_unique_feature_vectors": int(len(ground_truth)),
        "feature_count": len(FEATURES), "target": "label", "excluded_from_model": ["difficulty", "source_file", "source_row_one_based"],
        "class_count": int(ground_truth.label.nunique()), "ground_truth_sha256": sha256(ground_truth_path),
    }
    write_json(output / "manifest.json", manifest)
    (output / "README.md").write_text(
        "# Ground truth riêng của dự án\n\n"
        "Gộp KDDTrain+.txt và KDDTest+.txt đầy đủ. Không cộng hai file subset để tránh nhân bản mẫu. "
        "Mỗi hàng model-ready có 41 feature và một nhãn gốc. Difficulty/provenance không phải feature.\n\n"
        "Các vector 41 feature có nhiều nhãn trái ngược được đưa vào `quarantined_label_conflicts.csv`. "
        "Các vector trùng nhưng cùng nhãn được giữ một bản; chi tiết nằm trong `deduplicated_consistent_records.csv`.\n\n"
        "Bộ này trộn train/test chuẩn của NSL-KDD, nên kết quả split mới chỉ có ý nghĩa nội bộ và không so sánh trực tiếp với benchmark chuẩn.\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
