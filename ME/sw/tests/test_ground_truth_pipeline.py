import unittest

import numpy as np
import pandas as pd

from ME.sw.train_model.train_decision_tree_ground_truth import three_way_split


class GroundTruthSplitTests(unittest.TestCase):
    def test_split_is_complete_disjoint_reproducible_and_class_aware(self):
        y = pd.Series(["large"] * 100 + ["small"] * 3 + ["tiny"] * 2)
        first = three_way_split(y)
        second = three_way_split(y)
        for left, right in zip(first, second):
            np.testing.assert_array_equal(left, right)
        train, validation, test = map(set, first)
        self.assertFalse(train & validation or train & test or validation & test)
        self.assertEqual(train | validation | test, set(range(len(y))))
        self.assertEqual([sum(y.iloc[list(ids)] == "small") for ids in first], [1, 1, 1])
        self.assertEqual([sum(y.iloc[list(ids)] == "tiny") for ids in first], [1, 0, 1])


if __name__ == "__main__":
    unittest.main()
