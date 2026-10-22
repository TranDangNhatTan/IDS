import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from ME.sw.paths import GROUND_TRUTH_MODEL_DIR
from ME.sw.runtime.laptop_preprocessing import FeatureValidationError, canonicalize
from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, NUMERIC


class LaptopPreprocessingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model_dir = GROUND_TRUTH_MODEL_DIR

    def valid_row(self):
        row = {feature: 0 for feature in FEATURES}
        row.update({"protocol_type": "tcp", "service": "http", "flag": "SF"})
        return pd.DataFrame([row])

    def test_numeric_features_become_float32_in_order(self):
        features, audit = canonicalize(self.valid_row(), self.model_dir)
        self.assertEqual(list(features.columns), FEATURES)
        self.assertTrue(all(features[feature].dtype == np.float32 for feature in NUMERIC))
        self.assertEqual(audit["unknown_categories"], {feature: [] for feature in CATEGORICAL})

    def test_numeric_values_are_rounded_to_six_decimals_before_float32(self):
        frame = self.valid_row()
        frame["serror_rate"] = [0.123456789]
        features, audit = canonicalize(frame, self.model_dir)
        self.assertAlmostEqual(float(features.loc[0, "serror_rate"]), 0.123457, places=6)
        self.assertEqual(audit["decimal_rounding_places_before_float32"], 6)

    def test_invalid_rate_is_rejected(self):
        frame = self.valid_row()
        frame["serror_rate"] = frame["serror_rate"].astype(np.float32)
        frame.loc[0, "serror_rate"] = 1.1
        with self.assertRaisesRegex(FeatureValidationError, "Rate outside"):
            canonicalize(frame, self.model_dir)

    def test_unknown_category_matches_non_strict_contract(self):
        frame = self.valid_row()
        frame.loc[0, "service"] = "new_service"
        features, audit = canonicalize(frame, self.model_dir)
        self.assertEqual(features.loc[0, "service"], "new_service")
        self.assertEqual(audit["unknown_categories"]["service"], ["new_service"])
        with self.assertRaises(FeatureValidationError):
            canonicalize(frame, self.model_dir, strict_categories=True)


if __name__ == "__main__":
    unittest.main()
