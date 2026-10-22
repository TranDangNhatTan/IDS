"""Validate canonical float32 features and predict with the saved ground-truth Decision Tree."""

import argparse
import json
from pathlib import Path

import joblib
import pandas as pd

from ME.sw.paths import GROUND_TRUTH_MODEL_DIR, HW_EXPORT_DIR, TREE_DIR
from ME.sw.runtime.laptop_preprocessing import canonicalize, read_input
from ME.sw.train_model.train_decision_tree import FEATURES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="CSV with headers or headerless 43-field NSL-KDD TXT")
    parser.add_argument("--input-format", choices=["auto", "csv", "nsl-kdd"], default="auto")
    parser.add_argument("--model-dir", type=Path, default=GROUND_TRUTH_MODEL_DIR)
    parser.add_argument("--hardware-export-dir", type=Path, default=HW_EXPORT_DIR)
    parser.add_argument("--output", type=Path, default=TREE_DIR / "laptop_predictions.csv")
    parser.add_argument("--strict-categories", action="store_true", help="Reject categories absent from the training encoder")
    args = parser.parse_args()
    raw = read_input(args.input, args.input_format)
    features, audit = canonicalize(raw, args.model_dir, strict_categories=args.strict_categories, hardware_export_dir=args.hardware_export_dir)
    model = joblib.load(args.model_dir / "pipeline.joblib")
    prediction = model.predict(features)
    probability = model.predict_proba(features)
    output = pd.DataFrame({"row_zero_based": range(len(features)), "predicted_type": prediction,
                           "max_leaf_fraction_not_calibrated": probability.max(axis=1)})
    if "label" in raw.columns:
        output.insert(1, "actual_type", raw.label.astype(str).str.strip())
        output["correct_type"] = output.actual_type.eq(output.predicted_type)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False)
    audit["model_dir"] = str(args.model_dir.resolve())
    audit["input"] = str(args.input.resolve())
    audit["output"] = str(args.output.resolve())
    audit["warning"] = "max_leaf_fraction_not_calibrated is a Decision Tree leaf class fraction, not a calibrated probability."
    args.output.with_suffix(".audit.json").write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Predicted {len(output)} records using canonical float32 numeric features.")
    print(f"Output: {args.output}")


if __name__ == "__main__":
    main()
