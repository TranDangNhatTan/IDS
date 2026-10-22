# 02 — Pipeline software và runtime

## Module chính

| Package | Vai trò |
|---|---|
| `ME.sw.feature_contract` | Load profile, validate và encode feature integer. |
| `ME.sw.train_model.train_hardware_tree` | Train/tune Decision Tree hardware-aware bằng CPU. |
| `ME.sw.export_model.h5_tree` | Ghi/đọc deployment model HDF5 integer-only. |
| `ME.sw.export_model.export_hardware_model` | HDF5 → node CSV → ROM → golden vectors. |
| `ME.sw.runtime.fixed_tree_evaluator` | Traversal integer dùng chung cho CSV/ROM. |
| `ME.sw.runtime.predict_integer_tree` | CLI inference không dùng sklearn/joblib/HDF5. |

## Preprocessing duy nhất

```text
raw record
  → validate feature/category/range
  → category enum
  → byte divisor
  → rate Q0.16
  → saturation
  → ordered integer vector
```

Train và hardware export dùng cùng `FeatureProfile`; không có một preprocessing riêng âm thầm cho FPGA.

## Training CPU

```bat
.\.venv\Scripts\python.exe -m ME.sw.train_model.train_hardware_tree --profile fpga_flow28 --backend cpu
```

Trainer thử các cặp `max_depth`/`min_samples_leaf`, chọn theo validation macro-F1 với tolerance 0,005 rồi ưu tiên tree ít node, recall cao và FPR thấp hơn. Output directory dùng `exist_ok=False` để tránh ghi đè evidence cũ.

## HDF5 integer

`model_integer.h5` chứa các dataset:

```text
operation   uint8
feature_id  uint8
operand     uint32 (được validate vừa 22 bit)
true_child  uint16
false_child uint16
class_id    uint8
```

File không chứa pickle object, sklearn estimator hoặc floating threshold.

## Inference thuần integer

```bat
.\.venv\Scripts\python.exe -m ME.sw.runtime.predict_integer_tree --nodes-csv ME\hw\model_export\dt_fpga_flow28_fixed\fpga_tree_nodes.csv --schema ME\hw\model_export\dt_fpga_flow28_fixed\fpga_input_schema.csv --input ME\hw\model_export\dt_fpga_flow28_fixed\golden_vectors.csv --output ME\hw\model_export\dt_fpga_flow28_fixed\predictions_from_csv.csv
```

CLI kiểm tra input unsigned, bit width, saturation và feature order trước traversal. Với golden set hiện tại: 22.156 rows, 0 class mismatch, 0 leaf mismatch.

## Regression

```bat
.\.venv\Scripts\python.exe -m unittest discover -s ME\sw\tests -v
```

Test bao phủ split, preprocessing cũ, integer/Q0.16 encoding, HDF5 integer round-trip, node pack/unpack và CUDA fail-fast.
