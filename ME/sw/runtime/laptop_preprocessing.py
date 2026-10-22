"""Canonical float32 preprocessing for the trained NSL-KDD Decision Tree on a laptop."""

import json
from pathlib import Path

import numpy as np
import pandas as pd

from ME.sw.paths import HW_EXPORT_DIR
from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, NUMERIC


RATES = {
    "serror_rate", "srv_serror_rate", "rerror_rate", "srv_rerror_rate", "same_srv_rate",
    "diff_srv_rate", "srv_diff_host_rate", "dst_host_same_srv_rate", "dst_host_diff_srv_rate",
    "dst_host_same_src_port_rate", "dst_host_srv_diff_host_rate", "dst_host_serror_rate",
    "dst_host_srv_serror_rate", "dst_host_rerror_rate", "dst_host_srv_rerror_rate",
}
BOOLEAN = {"land", "logged_in", "root_shell", "is_host_login", "is_guest_login"}
DECIMAL_PLACES = 6


class FeatureValidationError(ValueError):
    """Input cannot safely be passed to the trained feature pipeline."""


def load_contract(model_dir, hardware_export_dir=HW_EXPORT_DIR):
    model_dir = Path(model_dir)
    schema = json.loads((model_dir / "feature_schema.json").read_text(encoding="utf-8"))
    if schema["raw_features"] != FEATURES or schema["categorical_features"] != CATEGORICAL:
        raise FeatureValidationError("Model feature schema does not match this project contract")
    hardware_export_dir = Path(hardware_export_dir)
    ranges = pd.read_csv(hardware_export_dir / "fpga_input_schema.csv").set_index("raw_feature")
    categories = pd.read_csv(hardware_export_dir / "fpga_category_codes.csv")
    allowed = {feature: set(categories.loc[categories.raw_feature.eq(feature), "category"].astype(str)) for feature in CATEGORICAL}
    return schema, ranges, allowed


def canonicalize(frame, model_dir, strict_categories=False, hardware_export_dir=HW_EXPORT_DIR):
    """Return 41 ordered features with 38 float32 numbers and 3 strings.

    Unknown categories are retained by default: the saved sklearn encoder maps
    them to all-zero one-hot vectors, matching the FPGA code-0 contract.
    """
    _, ranges, allowed = load_contract(model_dir, hardware_export_dir)
    duplicate = frame.columns[frame.columns.duplicated()].tolist()
    if duplicate:
        raise FeatureValidationError(f"Duplicate column names: {duplicate}")
    missing = [feature for feature in FEATURES if feature not in frame.columns]
    if missing:
        raise FeatureValidationError(f"Missing required features: {missing}")
    result = frame.loc[:, FEATURES].copy()
    for feature in CATEGORICAL:
        if result[feature].isna().any():
            raise FeatureValidationError(f"Missing categorical value in {feature}")
        result[feature] = result[feature].astype(str).str.strip()
        unknown = sorted(set(result[feature]) - allowed[feature])
        if unknown and strict_categories:
            raise FeatureValidationError(f"Unknown {feature} values: {unknown}")
    for feature in NUMERIC:
        # Round in float64 first, then cast to float32. This makes the decimal
        # contract explicit even though IEEE-754 float32 cannot represent every
        # base-10 value exactly in binary.
        result[feature] = pd.to_numeric(result[feature], errors="raise").round(DECIMAL_PLACES).astype(np.float32)
        values = result[feature].to_numpy()
        if not np.isfinite(values).all():
            raise FeatureValidationError(f"Non-finite value in {feature}")
        if (values < 0).any():
            raise FeatureValidationError(f"Negative value in non-negative feature {feature}")
        if feature in RATES and ((values < 0).any() or (values > 1).any()):
            raise FeatureValidationError(f"Rate outside [0, 1] in {feature}")
        if feature in BOOLEAN and not np.isin(values, [0.0, 1.0]).all():
            raise FeatureValidationError(f"Boolean feature must be 0 or 1: {feature}")
    audit = {
        "row_count": len(result),
        "canonical_numeric_dtype": "float32",
        "decimal_rounding_places_before_float32": DECIMAL_PLACES,
        "category_dtype": "string",
        "unknown_categories": {feature: sorted(set(result[feature]) - allowed[feature]) for feature in CATEGORICAL},
        "outside_training_observed_range": {
            feature: int(((result[feature] < float(ranges.loc[feature, "observed_min"])) |
                          (result[feature] > float(ranges.loc[feature, "observed_max"]))).sum())
            for feature in NUMERIC
        },
    }
    return result, audit


def read_input(path, input_format="auto"):
    """Read either a header CSV or the original 43-column NSL-KDD TXT form."""
    path = Path(path)
    if input_format == "nsl-kdd" or (input_format == "auto" and path.suffix.lower() == ".txt"):
        names = FEATURES + ["label", "difficulty"]
        return pd.read_csv(path, header=None, names=names)
    return pd.read_csv(path)
