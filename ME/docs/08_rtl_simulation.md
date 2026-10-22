# Phase 8 — Mô phỏng RTL bằng Icarus Verilog

Phase 8 của project này chỉ compile và mô phỏng RTL. Không chạy synthesis, implementation, timing analysis hoặc tạo bitstream.

## Yêu cầu

- `iverilog` và `vvp` có trong `PATH`.
- Python virtual environment `.venv` để sinh test vector từ golden CSV.
- Chạy từ root project.

## Chạy toàn bộ bằng CMD

```bat
ME\hw\scripts\run_icarus.bat
```

Đổi số golden vector:

```bat
ME\hw\scripts\run_icarus.bat --vectors 512
```

Hoặc gọi Python trực tiếp:

```bat
.\.venv\Scripts\python.exe -m ME.hw.scripts.run_icarus_sim
```

## Luồng runner

1. `generate_icarus_vectors.py` pack golden CSV thành bus Verilog.
2. Compile từng testbench với `iverilog -g2005`.
3. Chạy `.vvp` bằng `vvp`.
4. Kiểm tra PASS token và không có `FAIL`/`TIMEOUT`.
5. Ghi log và `simulation_report.json`.

## Testbench

| Testbench | Phạm vi |
|---|---|
| `tb_feature_blocks.v` | Rate quantizer, history window, Ethernet/IPv4/TCP parser. |
| `tb_ids_tree_engine.v` | Node ROM/FSM trên golden feature snapshot. |
| `tb_ids_top.v` | Raw 32-bit feature → quantizer → tree. |
| `tb_ids_packet_top.v` | Hai packet bidirectional → đóng flow → tree result. |

## Kết quả hiện tại

```text
FEATURE_BLOCKS_PASS
TREE_ENGINE_PASS vectors=22156 max_steps=20
IDS_TOP_PASS vectors=22156
PACKET_TOP_PASS class=18 leaf=1087
RTL_SIMULATION_PASS tests=4 vectors=22156 synthesis=false
```

Kết quả máy đọc nằm tại:

```text
ME/hw/sim/results/simulation_report.json
ME/hw/sim/results/*.log
```

File `.vvp` chỉ là output compile tạm tại `ME/hw/sim/build/`.

## Tiêu chí PASS

- Tree engine phải khớp class và leaf của golden vector.
- Top-level preprocessing phải cho cùng class/leaf.
- Invalid feature phải trả error thay vì tự thay bằng zero.
- Parser/rate/history unit test không có mismatch.
- Runner phải ghi `synthesis_run: false`.
