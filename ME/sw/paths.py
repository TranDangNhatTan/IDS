"""Canonical locations for the reorganized project tree."""

from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
ME_ROOT = PROJECT_ROOT / "ME"
RAW_DATA_DIR = ME_ROOT / "sw" / "dataset" / "raw" / "NSL-KDD-DataSet-master"
GROUND_TRUTH_DIR = ME_ROOT / "sw" / "dataset" / "ground_truth"
TREE_DIR = ME_ROOT / "sw" / "tree"
GROUND_TRUTH_MODEL_DIR = TREE_DIR / "decision_tree_ground_truth"
HW_EXPORT_DIR = ME_ROOT / "hw" / "model_export" / "decision_tree_ground_truth"
