"""Generate packed Verilog test vectors from the canonical golden CSV."""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def write_hex(path: Path, values: list[int], digits: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{value:0{digits}X}\n" for value in values), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-dir", type=Path, default=Path("ME/hw/model_export/dt_fpga_flow28_fixed"))
    parser.add_argument("--output-dir", type=Path, default=Path("ME/hw/tb/data"))
    parser.add_argument("--count", type=int, default=22156)
    args = parser.parse_args()
    schema = pd.read_csv(args.export_dir / "fpga_input_schema.csv").sort_values("feature_id")
    golden = pd.read_csv(args.export_dir / "golden_vectors.csv").head(args.count)
    if len(golden) != args.count:
        raise ValueError(f"Requested {args.count} vectors, found {len(golden)}")

    encoded_words: list[int] = []
    raw_words: list[int] = []
    expected_words: list[int] = []
    for row in golden.itertuples(index=False):
        encoded_word = 0
        raw_word = 0
        for item in schema.itertuples(index=False):
            code = int(getattr(row, item.raw_feature))
            encoded_word |= code << (int(item.feature_id) * 22)
            if item.representation == "UINT_SAT":
                raw = code * int(item.scale)
            else:
                # Categories are already enum codes; rates are already Q0.16.
                raw = code
            raw_word |= raw << (int(item.feature_id) * 32)
        encoded_words.append(encoded_word)
        raw_words.append(raw_word)
        expected_words.append((int(row.expected_leaf_node) << 6) | int(row.expected_class_id))

    write_hex(args.output_dir / "tree_features.mem", encoded_words, (28 * 22) // 4)
    write_hex(args.output_dir / "raw_features.mem", raw_words, (28 * 32) // 4)
    write_hex(args.output_dir / "expected_results.mem", expected_words, 5)
    (args.output_dir / "vector_count.vh").write_text(f"`define RTL_VECTOR_COUNT {args.count}\n", encoding="ascii")
    print(f"Generated {args.count} vectors in {args.output_dir}")


if __name__ == "__main__":
    main()
