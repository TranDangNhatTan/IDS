# 03 — Contract fixed-point và input FPGA

## Profile release

`fpga_flow28` có 28 feature theo đúng thứ tự trong `fpga_input_schema.csv`. RTL dùng feature ID 0–27; mọi giá trị được zero-extend thành 22 bit trong feature register.

| Nhóm | Representation |
|---|---|
| `protocol_type` | UINT2 category code |
| `service` | UINT7 category code |
| `flag` | UINT4 category code |
| 15 rate feature | UINT16 Q0.16, scale 65535 |
| Count/basic | Unsigned saturating integer |

Category code 0 là unknown. Mapping đầy đủ nằm trong `fpga_category_codes.csv`.

## Scale byte

```text
src_bytes_code = min(floor(src_bytes / 4), 240748)
dst_bytes_code = min(floor(dst_bytes / 64), 3309)
```

Các counter khác dùng divisor 1 và saturation riêng theo schema.

## Rate Q0.16

```text
code = round_to_nearest_ties_even(clamp(numerator/denominator, 0, 1) × 65535)
```

Chia zero phải tạo error/valid policy rõ ràng; `ids_rate_quantizer` trả `divide_by_zero=1` và code 0. Không được wrap khi overflow.

## Node operations

| Operation | Điều kiện |
|---|---|
| `NUMERIC_LE` | `feature_code <= operand` |
| `CATEGORY_EQ` | `category_code == operand` |
| `LEAF` | xuất `class_id` |

One-hot categorical của sklearn đã được exporter đổi thành equality trên category code, nên RTL không cần bus one-hot 121 feature.

## Artifact release

```text
ME/hw/model_export/dt_fpga_flow28_fixed/
├── fpga_input_schema.csv
├── fpga_category_codes.csv
├── class_map.csv
├── fpga_tree_nodes.csv
├── node_words.csv
├── node_rom.mem/.hex/.coe/.mif
├── golden_vectors.csv
├── golden_paths.csv
├── model_manifest.json
└── parity_report.json
```

`node_rom.mem` là file RTL `$readmemh`; CSV dùng cho audit, không parse trong FPGA.

## Parity đã chứng minh

Trên toàn bộ 147.674 record:

```text
sklearn prediction = integer HDF5/CSV prediction = packed ROM prediction
```

Golden vector đã saturation theo schema; không có giá trị vượt bit width.
