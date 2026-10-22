"""Convert an offline sklearn run into the integer-only deployment model .h5."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib

from ME.sw.export_model.export_hardware_model import export_nodes
from ME.sw.export_model.h5_tree import load_h5, save_h5
from ME.sw.feature_contract.schema import load_profile


def create(model_dir: Path) -> Path:
    model_dir = model_dir.resolve()
    run = json.loads((model_dir / "run_metadata.json").read_text(encoding="utf-8"))
    profile = load_profile(run["profile"])
    category_codes = json.loads((model_dir / "category_codes.json").read_text(encoding="utf-8"))
    class_ids = json.loads((model_dir / "class_map.json").read_text(encoding="utf-8"))
    model = joblib.load(model_dir / "pipeline.joblib")
    nodes, _ = export_nodes(model, profile, class_ids)
    output = model_dir / "model_integer.h5"
    save_h5(output, nodes, profile_name=profile.name, profile_sha256=profile.sha256,
            feature_names=profile.features, category_codes=category_codes, class_ids=class_ids)
    restored, metadata = load_h5(output)
    if restored != nodes or metadata["profile_sha256"] != profile.sha256:
        raise AssertionError("HDF5 round-trip changed the integer tree")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    args = parser.parse_args()
    print(create(args.model_dir))


if __name__ == "__main__":
    main()
