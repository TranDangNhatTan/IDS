# Đặc tả tiền xử lý FPGA — Decision Tree ground truth

Đặc tả này xuất trực tiếp từ `pipeline.joblib`. `fpga_tree_nodes.csv` không cần tạo 121 one-hot bit: node category được chuyển thành so sánh mã category. Parity check đã kiểm tra toàn bộ ground truth sạch và cho cùng nhãn với sklearn.

## Đồng bộ và luồng dữ liệu

1. RX MAC tạo stream packet trong clock domain RX: `data`, `valid`, `ready`, `last`, `timestamp`.
2. Nếu RX clock khác clock xử lý, qua asynchronous FIFO; không đưa state flow qua CDC từng bit. Descriptor hoặc record chỉ được đọc ở system clock sau FIFO.
3. Parser Ethernet/IPv4/L4 tạo flow key `(src_ip, dst_ip, src_port, dst_port, protocol)`. Với ICMP, thay port bằng type/code hoặc 0 theo quy ước cố định.
4. Flow-table update phải serialize read-modify-write theo flow key hoặc có hazard detector. Hai packet cùng flow không được cập nhật counter song song mất dữ liệu.
5. Khi FIN/RST hoặc timeout, đóng flow, chốt feature, giữ record stable cùng `feature_valid=1`, rồi đưa vào evaluator. Các counter và rate code phải stable đến khi `result_valid` được nhận.
6. Timeout/counter cần saturate theo fpga_input_schema.csv; overflow không được wrap. Feature thiếu phải có `feature_valid=0` và trả `unknown`, không thay bằng 0.

## Kiểu dữ liệu

- Categorical: protocol UINT2, service UINT7, flag UINT4. Code 0 là unknown; tại node category nó luôn đi nhánh not-equal, giống `OneHotEncoder(handle_unknown='ignore')`.
- Rate: UINT16 Q0.16. Mã hóa `round(clamp(numerator/denominator,0,1) * 65535)`. Cả feature và ngưỡng phải dùng cùng scale 65535.
- Integer: unsigned, saturating. Chiều rộng chính xác theo fpga_input_schema.csv. Không dùng float trong RTL.
- Duration: đơn vị phải thống nhất với train là giây nguyên. Nếu timestamp FPGA theo tick, dùng `duration = floor((end_tick-start_tick)/ticks_per_second)` trước khi đưa vào cây.

## Hạn chế quan trọng

Cây hiện tại dùng feature content: hot, num_failed_logins, logged_in, num_compromised, root_shell, su_attempted, num_root, num_file_creations, num_shells, num_access_files, is_host_login, is_guest_login. Các feature này yêu cầu payload/L7 parser hoặc telemetry host; header IPv4/TCP/UDP thuần không thể tạo tương đương. Không được gán 0 nếu muốn giữ độ chính xác model hiện tại. Nếu FPGA chỉ parse header/flow, phải train một cây mới chỉ với feature basic/time_window/host_window khả thi.

Các file liên quan: `fpga_input_schema.csv` (interface), `fpga_category_codes.csv` (enum), `fpga_tree_nodes.csv` (tree đã chuyển category/fixed-point), `feature_schema.json` (schema sklearn gốc).
