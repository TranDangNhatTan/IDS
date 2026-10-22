"""Compile and run every Phase 6-8 Verilog simulation with Icarus."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SIM_DIR = ROOT / "ME" / "hw" / "sim"
BUILD_DIR = SIM_DIR / "build"
RESULT_DIR = SIM_DIR / "results"

TREE = [
    "ME/hw/rtl/tree_engine/ids_tree_rom.v",
    "ME/hw/rtl/tree_engine/ids_node_decoder.v",
    "ME/hw/rtl/tree_engine/ids_feature_regfile.v",
    "ME/hw/rtl/tree_engine/ids_tree_engine.v",
]
FEATURE = [
    "ME/hw/rtl/feature_ingest/ids_rate_quantizer.v",
    "ME/hw/rtl/feature_ingest/ids_feature_quantizer.v",
    "ME/hw/rtl/feature_ingest/ids_feature_ingest.v",
    "ME/hw/rtl/feature_ingest/ids_packet_parser.v",
    "ME/hw/rtl/feature_ingest/ids_history_window.v",
    "ME/hw/rtl/feature_ingest/ids_single_flow_builder.v",
    "ME/hw/rtl/feature_ingest/ids_flow_table.v",
]
TOP = ["ME/hw/rtl/top/ids_top.v", "ME/hw/rtl/top/ids_packet_top.v"]


def execute(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    output = result.stdout + result.stderr
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{output}")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=int, default=22156,
                        help="number of held-out golden vectors (default: all 22156)")
    args = parser.parse_args()
    if shutil.which("iverilog") is None or shutil.which("vvp") is None:
        raise SystemExit("Icarus Verilog (iverilog and vvp) must be available in PATH")
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    execute([sys.executable, "ME/hw/scripts/generate_icarus_vectors.py", "--count", str(args.vectors)])

    cases = [
        ("feature_blocks", "tb_feature_blocks", FEATURE, "ME/hw/tb/tb_feature_blocks.v", "FEATURE_BLOCKS_PASS"),
        ("tree_engine", "tb_ids_tree_engine", TREE, "ME/hw/tb/tb_ids_tree_engine.v", "TREE_ENGINE_PASS"),
        ("feature_to_tree_top", "tb_ids_top", TREE + FEATURE[:3] + TOP[:1], "ME/hw/tb/tb_ids_top.v", "IDS_TOP_PASS"),
        ("packet_to_tree_top", "tb_ids_packet_top", TREE + FEATURE + TOP, "ME/hw/tb/tb_ids_packet_top.v", "PACKET_TOP_PASS"),
    ]
    report = {"simulator": execute(["iverilog", "-V"]).splitlines()[0], "vectors": args.vectors,
              "timestamp_utc": datetime.now(timezone.utc).isoformat(), "synthesis_run": False, "tests": {}}
    for name, top, sources, testbench, pass_token in cases:
        image = BUILD_DIR / f"{name}.vvp"
        compile_output = execute(["iverilog", "-g2005", "-s", top, "-o", str(image), *sources, testbench])
        run_output = execute(["vvp", str(image)])
        passed = pass_token in run_output and "_FAIL" not in run_output and "TIMEOUT" not in run_output
        (RESULT_DIR / f"{name}.log").write_text(compile_output + run_output, encoding="utf-8")
        report["tests"][name] = {"passed": passed, "pass_token": pass_token, "output": run_output.strip()}
        print(run_output.strip())
        if not passed:
            raise RuntimeError(f"Simulation did not report {pass_token}: {name}")
    (RESULT_DIR / "simulation_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"RTL_SIMULATION_PASS tests={len(cases)} vectors={args.vectors} synthesis=false")


if __name__ == "__main__":
    main()
