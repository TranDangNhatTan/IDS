#!/usr/bin/env python3
"""Convert hardware golden vectors to the dashboard's labeled 28-feature CSV."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT.parents[1] / "hw" / "model_export" / "dt_fpga_flow28_fixed" / "golden_vectors.csv"
DEFAULT_OUTPUT = ROOT / "demo_data" / "golden_10k_labeled.csv"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--count", type=int, default=10_000)
    args = parser.parse_args()
    if args.count < 1:
        raise ValueError("--count must be positive")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with args.input.open(newline="", encoding="utf-8") as source, args.output.open("w", newline="", encoding="utf-8") as target:
        reader, writer = csv.reader(source), csv.writer(target)
        header = next(reader)
        if len(header) != 32 or header[0:2] != ["vector_id", "source_row"] or header[-2:] != ["expected_class_id", "expected_leaf_node"]:
            raise ValueError("Unexpected golden-vector schema")
        writer.writerow(["label"] + [f"f{i}" for i in range(28)])
        for row in reader:
            if len(row) != 32:
                raise ValueError("Malformed golden-vector row")
            writer.writerow([row[30]] + row[2:30])
            written += 1
            if written == args.count:
                break
    if written != args.count:
        raise ValueError(f"Only {written} vectors available; expected {args.count}")
    print(f"Wrote {written} labeled vectors: {args.output}")


if __name__ == "__main__":
    main()
