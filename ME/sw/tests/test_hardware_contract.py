import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import h5py
import numpy as np
import pandas as pd

from ME.sw.export_model.h5_tree import load_h5, save_h5
from ME.sw.export_model.node_packer import pack_node, unpack_node
from ME.sw.export_model.tree_ir import validate_nodes
from ME.sw.feature_contract.encode import encode_frame
from ME.sw.feature_contract.schema import load_profile
from ME.sw.runtime.fixed_tree_evaluator import evaluate_one
from ME.sw.train_model.train_hardware_tree import cuda_backend_status


class HardwareContractTests(unittest.TestCase):
    def test_unavailable_cuda_backend_fails_instead_of_silent_cpu_fallback(self):
        with self.assertRaises(RuntimeError):
            cuda_backend_status("cuml")

    def test_profile_encoding_is_integer_and_rate_is_q016(self):
        profile = load_profile("fpga_flow28")
        frame = pd.DataFrame([{feature: 0 for feature in profile.features}], dtype=object)
        frame.loc[0, "protocol_type"] = "tcp"
        frame.loc[0, "service"] = "http"
        frame.loc[0, "flag"] = "SF"
        frame.loc[0, "same_srv_rate"] = 0.5
        categories = {"protocol_type": {"tcp": 1}, "service": {"http": 1}, "flag": {"SF": 1}}
        encoded = encode_frame(frame, profile, categories)
        self.assertEqual(encoded.dtypes.nunique(), 1)
        self.assertEqual(int(encoded.loc[0, "same_srv_rate"]), 32768)

    def test_node_round_trip_and_integer_traversal(self):
        nodes = [
            {"node_id": 0, "operation": "NUMERIC_LE", "feature_id": 0, "operand": 5, "true_child": 1, "false_child": 2, "class_id": 0},
            {"node_id": 1, "operation": "LEAF", "feature_id": 0, "operand": 0, "true_child": 4095, "false_child": 4095, "class_id": 7},
            {"node_id": 2, "operation": "LEAF", "feature_id": 0, "operand": 0, "true_child": 4095, "false_child": 4095, "class_id": 9},
        ]
        validate_nodes(nodes, feature_count=1)
        unpacked = [unpack_node(pack_node(node), node["node_id"]) for node in nodes]
        self.assertEqual(evaluate_one(np.array([5]), unpacked)[:2], (7, 1))
        self.assertEqual(evaluate_one(np.array([6]), unpacked)[:2], (9, 2))

    def test_h5_deployment_model_is_integer_only_and_round_trips(self):
        nodes = [
            {"node_id": 0, "operation": "NUMERIC_LE", "feature_id": 0, "operand": 5, "true_child": 1, "false_child": 2, "class_id": 0},
            {"node_id": 1, "operation": "LEAF", "feature_id": 0, "operand": 0, "true_child": 4095, "false_child": 4095, "class_id": 7},
            {"node_id": 2, "operation": "LEAF", "feature_id": 0, "operand": 0, "true_child": 4095, "false_child": 4095, "class_id": 9},
        ]
        with TemporaryDirectory() as directory:
            path = Path(directory) / "tree.h5"
            save_h5(path, nodes, profile_name="test", profile_sha256="abc", feature_names=("x",),
                    category_codes={}, class_ids={"a": 7, "b": 9})
            restored, metadata = load_h5(path)
            self.assertEqual(restored, nodes)
            self.assertEqual(metadata["profile_sha256"], "abc")
            with h5py.File(path, "r") as handle:
                self.assertTrue(all(dataset.dtype.kind in "ui" for dataset in handle["nodes"].values()))

    def test_byte_divisor_is_applied_before_tree_inference(self):
        profile = load_profile("fpga_flow28")
        frame = pd.DataFrame([{feature: 0 for feature in profile.features}], dtype=object)
        frame.loc[0, "protocol_type"] = "tcp"; frame.loc[0, "service"] = "http"; frame.loc[0, "flag"] = "SF"
        frame.loc[0, "dst_bytes"] = 129
        categories = {"protocol_type": {"tcp": 1}, "service": {"http": 1}, "flag": {"SF": 1}}
        encoded = encode_frame(frame, profile, categories)
        self.assertEqual(int(encoded.loc[0, "dst_bytes"]), 2)


if __name__ == "__main__":
    unittest.main()
