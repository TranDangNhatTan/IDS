"""Small regression checks for data leakage boundaries and metric conventions."""

import tempfile
import json
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from ME.sw.train_model.train_decision_tree import CATEGORICAL, FEATURES, build_pipeline, load_dataset, metrics, write_json


class PipelineTests(unittest.TestCase):
    def test_binary_labels_and_excluded_fields(self):
        values = [0] * 41
        values[1:4] = ["tcp", "http", "SF"]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.txt"
            rows = [values + [label, difficulty] for label, difficulty in
                    [("normal", 1), ("neptune", 2), ("new_attack", 3)]]
            path.write_text("\n".join(",".join(map(str, row)) for row in rows), encoding="utf-8")
            X, y = load_dataset(path)
            self.assertEqual(list(X.columns), FEATURES)
            self.assertEqual(X.shape, (3, 41))
            self.assertEqual(y.tolist(), [0, 1, 1])

    def test_reject_short_record(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.txt"
            path.write_text(",".join(["0"] * 42), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "expected 43 fields"):
                load_dataset(path)

    def test_validation_categories_do_not_modify_encoder(self):
        X = pd.DataFrame(0, index=range(4), columns=FEATURES)
        for column, category in zip(CATEGORICAL, ["tcp", "http", "SF"]):
            X[column] = category
        X["src_bytes"] = [0, 1, 100, 101]
        pipeline = build_pipeline(2).fit(X, [0, 0, 1, 1])
        encoder = pipeline.named_steps["preprocess"].named_transformers_["categorical"]
        original = [categories.copy() for categories in encoder.categories_]
        validation = X.copy()
        validation.loc[:, CATEGORICAL] = "never_seen"
        self.assertEqual(len(pipeline.predict(validation)), 4)
        for before, after in zip(original, encoder.categories_):
            np.testing.assert_array_equal(before, after)
        encoded = pipeline.named_steps["preprocess"].transform(validation)
        if hasattr(encoded, "toarray"):
            encoded = encoded.toarray()
        np.testing.assert_array_equal(encoded[:, :3], np.zeros((4, 3)))

    def test_attack_positive_metrics_and_matrix_orientation(self):
        result = metrics([0, 0, 0, 0, 1, 1, 1], [0, 0, 0, 1, 0, 1, 1])
        self.assertEqual([result[key] for key in ["tn", "fp", "fn", "tp"]], [3, 1, 1, 2])
        self.assertAlmostEqual(result["false_positive_rate"], 1 / 4)
        self.assertAlmostEqual(result["recall_attack"], 2 / 3)
        self.assertAlmostEqual(result["precision_attack"], 2 / 3)
        self.assertAlmostEqual(result["f1_attack"], 2 / 3)
        self.assertAlmostEqual(result["accuracy"], 5 / 7)
        self.assertAlmostEqual(result["balanced_accuracy"], (2 / 3 + 3 / 4) / 2)

    def test_tree_statistics_can_be_saved_as_json(self):
        X = pd.DataFrame(0, index=range(4), columns=FEATURES)
        for column in CATEGORICAL:
            X[column] = "category"
        tree = build_pipeline(2).fit(X, [0, 0, 1, 1]).named_steps["model"]
        statistics = {"leaf_count": int(tree.get_n_leaves()), "node_count": int(tree.tree_.node_count), "actual_depth": int(tree.get_depth())}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "statistics.json"
            write_json(path, statistics)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), statistics)


if __name__ == "__main__":
    unittest.main()
