"""Load and validate immutable FPGA feature-profile configuration."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from ME.sw.train_model.train_decision_tree import FEATURES


CONFIG_DIR = Path(__file__).resolve().parents[2] / "config"


@dataclass(frozen=True)
class FeatureProfile:
    name: str
    features: tuple[str, ...]
    categorical_features: tuple[str, ...]
    rate_features: frozenset[str]
    boolean_features: frozenset[str]
    content_features: frozenset[str]
    integer_divisors: dict[str, int]
    rate_scale: int
    unknown_category_code: int
    sha256: str

    @property
    def numeric_features(self) -> tuple[str, ...]:
        categories = set(self.categorical_features)
        return tuple(feature for feature in self.features if feature not in categories)


def load_profile(name: str) -> FeatureProfile:
    # File names stay short while the externally visible profile name is explicit.
    config_name = {"fpga_flow28": "fpga_flow"}.get(name, name)
    path = CONFIG_DIR / f"feature_profile_{config_name}.json"
    raw = path.read_bytes()
    payload = json.loads(raw)
    features = tuple(payload["features"])
    if len(features) != len(set(features)) or not set(features).issubset(FEATURES):
        raise ValueError(f"Invalid feature list in {path}")
    categorical = tuple(payload["categorical_features"])
    if not set(categorical).issubset(features):
        raise ValueError(f"Categorical feature absent from profile {name}")
    rates = frozenset(payload["rate_features"])
    if not rates.issubset(features):
        raise ValueError(f"Rate feature absent from profile {name}")
    return FeatureProfile(
        name=payload["name"], features=features, categorical_features=categorical,
        rate_features=rates, boolean_features=frozenset(payload["boolean_features"]),
        content_features=frozenset(payload["content_features"]),
        integer_divisors={feature: int(value) for feature, value in payload.get("integer_divisors", {}).items()}, rate_scale=int(payload["rate_scale"]),
        unknown_category_code=int(payload["unknown_category_code"]),
        sha256=hashlib.sha256(raw).hexdigest(),
    )
