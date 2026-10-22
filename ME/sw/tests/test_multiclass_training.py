import unittest

import numpy as np
import pandas as pd

from ME.sw.train_model.multiclass_training import stratified_indices, score
from ME.sw.analysis.analyze_decision_tree_errors import attach_predictions, summarize_types


class MulticlassTests(unittest.TestCase):
    def test_rare_classes_have_no_leakage_and_are_represented(self):
        y = pd.Series(["normal"] * 80 + ["attack"] * 15 + ["rare"] * 3 + ["spy"] * 2)
        train, val = stratified_indices(y)
        self.assertEqual(len(val), 20)
        self.assertFalse(set(train) & set(val))
        self.assertEqual(set(train) | set(val), set(range(100)))
        self.assertEqual(set(y.iloc[train]), set(y))
        self.assertEqual(set(y.iloc[val]), set(y))
        np.testing.assert_array_equal(val, stratified_indices(y)[1])

    def test_wrong_attack_name_is_binary_detection_but_multiclass_error(self):
        result = score(["normal", "a", "unseen"], ["normal", "a", "a"], ["normal", "a", "unseen"])
        self.assertAlmostEqual(result["accuracy"], 2 / 3)
        self.assertEqual(result["binary_recall_attack"], 1)
        self.assertEqual(result["binary_false_positive_rate"], 0)
        self.assertAlmostEqual(result["macro_f1"], (1 + 2 / 3 + 0) / 3)

    def test_audit_joins_by_id_and_distinguishes_false_alarm_and_miss(self):
        raw = pd.DataFrame({"label": ["normal", "a", "b"]})
        saved = pd.DataFrame({"source_row_zero_based": [2, 0, 1], "actual": [1, 0, 1], "predicted": [1, 1, 0]})
        records = attach_predictions(raw, saved)
        self.assertEqual(records.outcome.tolist(), ["FP", "FN", "TP"])
        summary = summarize_types(records, pd.Series({"normal": 10, "a": 2}))
        self.assertEqual(summary.loc["a", "binary_attack_detection_recall"], 0)
        self.assertFalse(summary.loc["b", "seen_in_full_train"])
        self.assertTrue(np.isnan(summary.loc["normal", "binary_attack_detection_recall"]))
        with self.assertRaises(ValueError):
            attach_predictions(raw, saved.iloc[:2])


if __name__ == "__main__":
    unittest.main()
