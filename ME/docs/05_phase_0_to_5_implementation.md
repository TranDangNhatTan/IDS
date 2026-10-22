# Triển khai Phase 0–5: AI fixed-point cho FPGA

Tài liệu này là kế hoạch thực thi và contract chính thức cho các artifact dưới `ME/`. Mục tiêu là bảo đảm đường suy luận phần cứng không cần Python, sklearn, `.joblib`, `.h5`, số thực IEEE-754 hay CSV parser.

## Mục tiêu và phạm vi

Hai profile được xây dựng độc lập:

| Profile | Feature | Mục đích |
|---|---:|---|
| `full41` | 41 | So sánh chuẩn với model có đủ telemetry/L7; phù hợp SW feature extractor + FPGA tree evaluator. |
| `fpga_flow28` | 28 | Chỉ feature basic/time-window/host-window mà datapath FPGA có thể tạo; không giả lập content feature bằng 0. |

`DecisionTreeClassifier` không có weight như mạng neural. Model triển khai gồm node so sánh integer và class ID ở leaf. Sau training, `model_integer.h5` là container framework-neutral chứa các mảng node integer, profile hash, category codes và class map; nó không chứa pickle/sklearn hay threshold float. Exporter đọc `.h5` để sinh node CSV và ROM. FPGA không tự parse HDF5; artifact nạp vào FPGA vẫn là `.mem/.hex/.coe/.mif`.

## Phase 0 — Contract bất biến

Nguồn sự thật là `ME/config/`:

- `feature_profile_full41.json`, `feature_profile_fpga_flow.json`: thứ tự input, group và representation.
- `class_map.json`: mapping class string sang `class_id` 6-bit.
- `node_format.json`: bit layout node ROM 64-bit.
- `training_*.json`: không gian hyperparameter và objective chọn model.

Mọi artifact xuất ra phải chứa SHA-256 của profile/config và dataset; RTL chỉ được dùng ROM image có manifest khớp profile.

## Phase 1 — Fixed-point preprocessing

`ME.sw.feature_contract` thực hiện cùng một luồng cho train, reference và export:

```text
raw record → validate → category code / integer saturation / Q0.16 → ordered integer vector
```

- Category code: `0` là unknown; known code bắt đầu từ `1`.
- Rate: `UINT16`, `round(clamp(x, 0, 1) * 65535)`; Python dùng banker rounding (`np.rint`) và RTL phải tái hiện chính xác rule này hoặc phải dùng vector test để chứng minh equivalence.
- Integer: unsigned, `floor(raw / integer_divisor)` rồi `min(code, saturate_at)`, không wrap. `integer_divisor` là 1 nếu profile không ghi khác; ví dụ `dst_bytes` dùng divisor 64 để threshold luôn vừa trường operand 22-bit.
- Missing, NaN, negative, rate ngoài `[0, 1]`: reject, không đổi thành zero.

Feature content chỉ có trong `full41`. `fpga_flow28` không có chúng và do đó phải train model riêng.

## Phase 2 — Hardware-aware training

Script `ME.sw.train_model.train_hardware_tree` quantize dữ liệu **trước** khi fit. Numeric feature do đó đã là integer code ở lúc train. Category vẫn one-hot trong estimator nhằm tránh đặt thứ tự giả cho enum; exporter sẽ chuyển one-hot split thành `CATEGORY_EQ`.

CUDA: scikit-learn decision tree hiện dùng CPU; môi trường này không có `cuml`, `cupy` hoặc `torch`. Script nhận `--backend auto|cpu|cuml`; `auto` ghi rõ trạng thái và dùng sklearn CPU. `--backend cuml` fail-fast cho tới khi có adapter export/parity, tuyệt đối không âm thầm báo GPU nhưng train CPU. Backend không được phép đổi feature contract.

Model được chọn theo validation: macro-F1 cao nhất trong tolerance, sau đó node count nhỏ hơn, attack recall cao hơn và FPR thấp hơn. Test hold-out chỉ dùng sau chọn model.

## Phase 3 — Tree intermediate representation (IR)

Trainer tạo `model_integer.h5`; exporter đọc file này và tạo `fpga_tree_nodes.csv`, chỉ gồm logic phần cứng:

```text
node_id,operation,feature_id,operand,true_child,false_child,class_id
```

`NUMERIC_LE` sử dụng `feature <= operand`. `CATEGORY_EQ` có nhánh true khi `category_code == operand`; exporter đảo child sklearn phù hợp với split one-hot `<= 0.5`.

Validation bắt buộc: root node 0, child trong range, leaf không có child hữu hiệu, feature ID thuộc profile, operand vừa bit width feature, không cycle reachable, và mọi node reachable từ root.

## Phase 4 — ROM image

Một node có đúng một word 64-bit, packed theo `ME/config/node_format.json`:

```text
[63:62] operation    [61:56] feature_id    [55:34] operand
[33:22] true_child   [21:10] false_child   [9:4] class_id   [3:0] flags
```

`node_rom.mem` có một hexadecimal 64-bit word mỗi dòng. `node_words.csv` là bản audit với packed word. Packer/unpacker được kiểm tra round-trip; synthesis có thể dùng `$readmemh` trực tiếp.

## Phase 5 — Integer reference và golden vectors

`fixed_tree_evaluator.py` chỉ đọc profile + node CSV/ROM, không import sklearn. Golden vector chứa contract vector đã quantize **và saturation theo `fpga_input_schema.csv`**, leaf, class và node path; vì vậy mọi giá trị đều vừa đúng bit width của feature register. Các gate release:

```text
sklearn model prediction
== fixed-point node-CSV evaluator
== packed-ROM evaluator
```

RTL Phase 6 sau này phải đạt thêm:

```text
== RTL simulation result
```

## Artifact layout

```text
ME/sw/tree/<run_name>/                 # offline model, metrics, metadata
├── model_integer.h5                   # integer deployment model, input của exporter
ME/hw/model_export/<run_name>/
├── fpga_input_schema.csv
├── fpga_category_codes.csv
├── fpga_tree_nodes.csv
├── node_rom.mem / .hex / .coe / .mif
├── node_words.csv
├── class_map.csv
├── golden_vectors.csv
├── golden_paths.csv
├── parity_report.json
└── model_manifest.json
```

Không sửa tay file bên dưới `ME/hw/model_export/`; luôn regenerate từ run model tương ứng.

### Chạy inference thuần integer từ CSV hoặc ROM

Không dùng sklearn, joblib hay HDF5:

```powershell
# Đọc node CSV
.\.venv\Scripts\python.exe -m ME.sw.runtime.predict_integer_tree `
  --nodes-csv ME/hw/model_export/dt_fpga_flow28_fixed/fpga_tree_nodes.csv `
  --schema ME/hw/model_export/dt_fpga_flow28_fixed/fpga_input_schema.csv `
  --input ME/hw/model_export/dt_fpga_flow28_fixed/golden_vectors.csv `
  --output ME/hw/model_export/dt_fpga_flow28_fixed/predictions_from_csv.csv

# Hoặc giải mã trực tiếp ROM 64-bit
.\.venv\Scripts\python.exe -m ME.sw.runtime.predict_integer_tree `
  --rom-mem ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem `
  --schema ME/hw/model_export/dt_fpga_flow28_fixed/fpga_input_schema.csv `
  --input ME/hw/model_export/dt_fpga_flow28_fixed/golden_vectors.csv `
  --output ME/hw/model_export/dt_fpga_flow28_fixed/predictions_from_mem.csv
```

Input phải là feature code integer đúng schema. Nếu input có `expected_class_id` và `expected_leaf_node`, CLI trả exit code 1 khi có bất kỳ mismatch nào.

## Cách chạy và artifact đã tạo

Từ root repository:

```powershell
# Train profile chỉ gồm feature có thể tạo ở FPGA
.\.venv\Scripts\python.exe -m ME.sw.train_model.train_hardware_tree `
  --profile fpga_flow28 --backend cpu

# Export CSV logic, ROM image và golden vectors
.\.venv\Scripts\python.exe -m ME.sw.export_model.export_hardware_model `
  --model-dir ME/sw/tree/dt_fpga_flow28_fixed `
  --output-dir ME/hw/model_export/dt_fpga_flow28_fixed
```

Run đã được tạo trong workspace:

| Run | Nodes / depth | Test macro-F1 | Test attack recall | Test FPR | Parity |
|---|---:|---:|---:|---:|---|
| `dt_fpga_flow28_fixed` | 1,273 / 20 | 66.07% | 99.70% | 6.30% | PASS: model = HDF5 = node CSV = ROM, 147,674 rows |
| `dt_full41_fixed_v1` | 2,363 / 50 | 69.50% | 99.45% | 0.45% | PASS: model = node CSV = ROM, 147,674 rows |

`fpga_flow28` là artifact đúng để bắt đầu RTL parser/flow-only. `full41` chỉ là reference đầy đủ; nó vẫn cần telemetry/L7 cho content feature.

Máy chạy có NVIDIA RTX 4060 Laptop GPU, nhưng virtual environment hiện không cài cuML/CuPy/PyTorch. Vì `sklearn.DecisionTreeClassifier` không có CUDA backend, run chính được train tường minh bằng `--backend cpu` và ghi `sklearn-cpu` trong `run_metadata.json`; không được gọi nó là CUDA training. CUDA tree training chỉ được mở khi có cuML tương thích và đã có adapter/parity test để exporter nhận cùng tree semantics.

Ngày triển khai hiện tại, `wsl --status` xác nhận Ubuntu/WSL2 đã đăng ký, nhưng WSL không khởi động được vì thiếu file `ext4.vhdx` của distribution (`ERROR_PATH_NOT_FOUND`). Vì RAPIDS/cuML hỗ trợ ổn định trên Linux/WSL hơn Windows native, cần repair hoặc cài lại Ubuntu WSL trước khi cài RAPIDS. Đây là blocker môi trường, không phải lỗi model/export; artifact CPU hiện vẫn hoàn chỉnh và reproducible.
