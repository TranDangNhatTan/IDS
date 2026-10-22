# Phase 6 — Tree evaluator IP bằng Verilog

## Mục tiêu

Phase 6 triển khai cây `dt_fpga_flow28_fixed` thành datapath/FSM Verilog thuần, đọc trực tiếp `node_rom.mem`. RTL không đọc sklearn, joblib, HDF5 hoặc CSV và không sử dụng số thực.

## Cấu trúc source

| File | Chức năng |
|---|---|
| `ME/hw/rtl/tree_engine/ids_tree_rom.v` | ROM đồng bộ 64-bit, khởi tạo bằng `$readmemh`. |
| `ids_node_decoder.v` | Tách operation, feature ID, operand, child pointer và class ID. |
| `ids_feature_regfile.v` | Chốt 28 feature, mỗi feature zero-extend thành 22 bit. |
| `ids_tree_engine.v` | FSM duyệt cây và phát kết quả/error. |

Tất cả source dùng `.v` và biên dịch bằng `iverilog -g2005`.

## Node word 64-bit

```text
[63:62] operation
[61:56] feature_id
[55:34] operand
[33:22] true_child
[21:10] false_child
[ 9: 4] class_id
[ 3: 0] flags/reserved
```

Operation:

| Code | Ý nghĩa |
|---:|---|
| `00` | `LEAF` |
| `01` | `feature <= operand` |
| `10` | `feature == operand` |
| `11` | invalid |

Root luôn là node 0. Model hiện có 1.273 node nên child pointer 12-bit đủ. Class ID dùng 6 bit cho 40 lớp.

## Feature bus

Bus có `28 × 22 = 616 bit`:

```text
feature[i] = features_flat[i*22 +: 22]
```

Feature 0 nằm ở LSB. Giá trị có width nhỏ hơn 22 bit phải zero-extend. Thứ tự chính thức nằm trong `fpga_input_schema.csv`.

## FSM và timing

```text
IDLE → WAIT_ROM → EVALUATE → WAIT_ROM → ... → LEAF → IDLE
```

- `start && feature_valid && ready`: chốt toàn bộ feature và bắt đầu ở node 0.
- ROM là synchronous-read nên mỗi node dùng một chu kỳ chờ và một chu kỳ đánh giá.
- `result_valid` và `done` pulse một chu kỳ khi đến leaf.
- Worst-case model hiện tại là 20 decision steps; testbench quan sát đúng `max_steps=20`.
- `MAX_STEPS=64` bảo vệ khỏi ROM bị cycle/hỏng.

## Interface chính

| Signal | Hướng | Ý nghĩa |
|---|---|---|
| `start` | input | Pulse yêu cầu inference. |
| `feature_valid` | input | Snapshot feature hợp lệ. |
| `features_flat[615:0]` | input | 28 feature integer. |
| `ready`, `busy` | output | Trạng thái nhận request. |
| `done`, `result_valid` | output | Kết thúc và kết quả hợp lệ. |
| `class_id[5:0]` | output | Lớp dự đoán. |
| `leaf_node[11:0]` | output | Leaf để audit/debug. |
| `error_code[2:0]` | output | Lỗi contract/ROM. |

Error code: 0 không lỗi, 1 feature invalid, 2 operation invalid, 3 feature ID sai, 4 child pointer sai, 5 vượt step limit.

## Kết quả verification

`tb_ids_tree_engine.v` chạy toàn bộ 22.156 vector của held-out golden set:

```text
TREE_ENGINE_PASS vectors=22156 max_steps=20
```

Mỗi vector kiểm tra đồng thời `class_id`, `leaf_node`, `error_code` và thêm trường hợp `feature_valid=0`.
