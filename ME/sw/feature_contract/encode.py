"""Validation and deterministic integer encoding used before fit and inference."""

from __future__ import annotations

from typing import Mapping

import numpy as np
import pandas as pd

from .schema import FeatureProfile


def fit_category_codes(frame: pd.DataFrame, profile: FeatureProfile) -> dict[str, dict[str, int]]:
    """Assign codes in sorted lexical order; zero remains reserved for unknown."""
    return {
        feature: {value: code for code, value in enumerate(sorted(frame[feature].astype(str).str.strip().unique()), start=1)}
        for feature in profile.categorical_features
    }


def encode_frame(frame: pd.DataFrame, profile: FeatureProfile, category_codes: Mapping[str, Mapping[str, int]], *, strict_categories: bool = True) -> pd.DataFrame:
    missing = [feature for feature in profile.features if feature not in frame.columns]
    if missing:
        raise ValueError(f"Missing required features: {missing}")
    result = pd.DataFrame(index=frame.index)
    for feature in profile.categorical_features:
        raw = frame[feature]
        if raw.isna().any():
            raise ValueError(f"Missing categorical value in {feature}")
        labels = raw.astype(str).str.strip()
        mapping = category_codes[feature]
        unknown = sorted(set(labels.unique()) - set(mapping))
        if unknown and strict_categories:
            raise ValueError(f"Unknown {feature} values: {unknown}")
        result[feature] = labels.map(mapping).fillna(profile.unknown_category_code).astype(np.int64)
    for feature in profile.numeric_features:
        values = pd.to_numeric(frame[feature], errors="raise").to_numpy(dtype=np.float64)
        if not np.isfinite(values).all() or (values < 0).any():
            raise ValueError(f"{feature} must be finite and unsigned")
        if feature in profile.rate_features:
            if (values > 1).any():
                raise ValueError(f"Rate outside [0, 1] in {feature}")
            values = np.rint(np.clip(values, 0, 1) * profile.rate_scale)
        else:
            if not np.equal(values, np.floor(values)).all():
                raise ValueError(f"Integer feature has fractional value: {feature}")
            values = np.floor_divide(values.astype(np.int64), profile.integer_divisors.get(feature, 1))
        if feature in profile.boolean_features and not np.isin(values, [0, 1]).all():
            raise ValueError(f"Boolean feature must be 0 or 1: {feature}")
        result[feature] = values.astype(np.int64)
    return result.loc[:, profile.features]


def feature_bit_width(maximum: int) -> int:
    return max(1, int(maximum).bit_length())
