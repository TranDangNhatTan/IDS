# Báo cáo triển khai IP Final – FPGA IDS inline ACG525

## 1. Mục tiêu demo

Hệ thống minh họa IDS chạy trên FPGA ACG525 ở chế độ inline monitor:
FPGA nằm giữa máy A và máy B để chuyển tiếp Ethernet hai chiều, đồng thời
quan sát lưu lượng đi từ A sang B và phân loại bằng Decision Tree.

Nguyên tắc thiết kế là Ethernet forwarding hoạt động độc lập với IDS. Nếu model
chưa nạp, đang nạp model hoặc IDS có lỗi, bridge Ethernet vẫn tiếp tục chuyển
frame. IDS không được phép sở hữu hoặc chặn chân TX Ethernet.

## 2. Kiến trúc vật lý

    Máy A / router
           |
           | Ethernet 100 Mb/s
           v
    LAN8720 (RMII) <--> FPGA ACG525 <--> RTL8211F (RGMII) <--> Máy B / switch
                          |
                          | UART TTL 3.3 V, 115200, 8-N-1
                          v
                  Laptop / server web local

UART là TTL 3.3 V, không phải RS-232. Dây theo constraint hiện tại: FPGA V8
(TX) sang RX adapter, TX adapter sang FPGA V7 (RX), và GND chung. Chân V7 phải
được đối chiếu với sơ đồ board thực tế trước khi cắm.

## 3. Luồng dữ liệu Ethernet và IDS

    RMII RX
      |-- bridge đã kiểm chứng --> RGMII TX --> Máy B
      |       (đường chuyển tiếp không phụ thuộc IDS)
      |
      '-- RMII deserializer monitor
              --> packet parser
                  --> flow table
                      --> history features
                          --> feature quantizer
                              --> Decision Tree
                                  --> UART telemetry

Top module là top_acg525_inline_ids.v. Nó dùng bridge
top_acg525_rgmii_rmii_bridge làm chủ duy nhất của các chân TX Ethernet. Một
RMII deserializer thứ hai chỉ đọc cùng tín hiệu RMII để monitor và không can
thiệp forwarding. Phiên bản hiện tại classify chiều A sang B; chiều ngược lại
vẫn bridge nhưng chưa classify.

## 4. Nội dung thư mục IP final

    ME/fpga/ip_final/
    |-- src/
    |   |-- top_acg525_inline_ids.v       top board
    |   |-- model_update_uart.v           giao thức nạp model
    |   |-- ids_tree_rom_banked.v         RAM model writable
    |   |-- ids_tree_engine_live.v        suy luận Decision Tree
    |   |-- ids_packet_top_live.v         parser, flow, history, classifier
    |   |-- ids_uart_telemetry.v          log kết quả UART
    |   |-- ip_final.cst, ip_final.sdc    pin và timing constraint
    |   '-- deps/                         snapshot dependency RTL nội bộ
    |-- model/node_rom.mem                1.273 node để upload
    |-- server/ids_web_server.py          dashboard local và UART uploader
    |-- scripts/                          verify, traffic máy A và B
    |-- tb/                               testbench
    |-- build_gowin.tcl, ip_final.gprj    project Gowin
    '-- docs/                             tài liệu

Toàn bộ RTL mà project Gowin dùng đã ở src/deps hoặc src. Hai file project
không còn tham chiếu RTL từ demo_connect hay ME/hw/rtl. Model image cũng nằm
trong chính ip_final.

## 5. Feature và Decision Tree

Packet parser trích trường L2/L3/L4. Flow table gom packet theo 5-tuple hai
chiều, theo dõi byte, thời gian, fragment và urgent flag. Khi TCP flow đóng
hoặc timeout, nó tạo raw record 28 feature:

1. Chín feature flow: duration, protocol, service, flag, source bytes,
   destination bytes, land, wrong fragment, urgent.
2. Mười chín feature history theo host và service.

ids_feature_ingest lượng tử hóa feature theo profile model. ids_tree_engine_live
duyệt Decision Tree và xuất class_id, leaf_node, step_count, error_code.

Model dt_fpga_flow28_fixed có kết quả software trên tập test có nhãn:

| Chỉ số | Giá trị |
|---|---:|
| Accuracy test | 95.4775% |
| Macro F1 | 66.07% |
| Attack recall | 99.70% |
| False-positive rate | 6.30% |

Các số này chỉ là accuracy trên dataset có ground truth, không phải accuracy
của traffic demo live không nhãn.

## 6. Nạp model qua UART

Sau mỗi lần FPGA cấu hình, model RAM trống. Laptop/server phải upload
model/node_rom.mem rồi activate model trước khi IDS classify packet. Ethernet
forwarding vẫn hoạt động trong giai đoạn này.

Giao thức UART:

    Begin image: A5 5A 12 12
    Write node : A5 5A 10 addr_lo addr_hi data_byte_0 ... data_byte_7 XOR
    Activate   : A5 5A 11 11

- data byte 0 là bits 7:0 của node word 64-bit, little endian.
- Checksum là XOR của command và payload.
- FPGA chỉ activate khi nhận đủ 1.273 word.
- Frame checksum sai bị bỏ và đặt cờ checksum_error.
- Trong update, classification bị gate để không đọc node đang thay đổi.

Server ids_web_server.py mở dashboard tại http://127.0.0.1:8080. Nút Upload
node_rom.mem gửi begin, toàn bộ write command, rồi activate.

## 7. UART telemetry

Mỗi inference hoàn tất phát một dòng:

    IDS,<class_hex>,<leaf_hex>,<steps_hex>,<error>,<bank>,<version_hex>

Dashboard hiển thị event, tổng kết quả, alert count, leaf, số step và model
version. Dashboard chỉ được báo prediction, event rate và metric vận hành.
Không được tự báo live accuracy nếu chưa replay traffic có nhãn để đối chiếu.

## 8. Kiểm chứng đã thực hiện

| Kiểm tra | Kết quả | Ý nghĩa |
|---|---|---|
| Model, CSV, ROM parity | 147.674 giá trị feature | Export mapping đúng |
| Tree RTL parity | 22.156 / 22.156 vector | RTL khớp golden model |
| Model-update UART TB | MODEL_UPDATE_UART_PASS words=1273 | Giao thức upload đúng |
| BRAM history TB | HISTORY_BRAM_PASS cycles=8 time_count=2 | RAM tuần tự đúng |
| Local top elaboration | IP_FINAL_LOCAL_RTL_LINT_PASS | Local RTL compile qua top |

Tree RTL parity 100% có nghĩa RTL khớp leaf/nhãn golden do software tạo. Nó
không thay thế dataset accuracy 95.4775%.

Chạy regression trước build:

    cd ME\fpga\ip_final
    .\scripts\verify_ip_final.ps1

Kết quả cần có HISTORY_BRAM_PASS, MODEL_UPDATE_UART_PASS và
IP_FINAL_VERIFY_PASS.

## 9. Kiến trúc bộ nhớ và tối ưu tài nguyên

### Model RAM

ids_tree_rom_banked.v dùng primitive DPB trực tiếp của GW5A, không chỉ dùng
ram_style = block. Model 1.273 x 64 bit được tổ chức thành hai bank 1.024 x
64 bit; mỗi bank 64-bit dùng bốn DPB 1.024 x 16 bit. Tổng cộng model chiếm
8 macro BSRAM 16-Kbit. Port A ghi từ UART; port B đọc cho tree engine.
RAM writable runtime và không dùng readmemh, tránh tool mở rộng RAM initialized
writable quá lớn.

Sau PNR, utilization report phải thể hiện tối thiểu 8 BSRAM do tree model.
Đây là bằng chứng macro đã được place. Attribute hoặc dòng log Extracting RAM
không còn là bằng chứng đủ.

### Flow table

ids_flow_table có 16 entry và lookup fully-associative một chu kỳ. Nó chỉ vài
Kbit nhưng phải so sánh song song. Giữ nó thành register/LUT hợp lý hơn ép vào
một block RAM 16-Kbit, vốn lãng phí và làm mất lookup một chu kỳ.

### History window

ids_history_window.v là functional reference, scan 256 entry song song để
trả history trong cycle flow đóng. Nó phù hợp simulation/parity, không phù hợp
một BRAM một cổng.

src/deps/ids_history_window_bram.v pack entry 92-bit vào RAM block, đọc một
entry mỗi chu kỳ. Query depth 256 mất 2 x 256 + 1 = 513 chu kỳ; với clock
50 MHz là khoảng 10.26 microsecond/query.

Profile Gowin hiện dùng ids_packet_top_resource, ids_flow_table_resource và
ids_history_pipeline_resource; nó không còn dùng ids_history_window.v hoặc
ids_flow_table.v reference. Khi flow đóng, pipeline giữ base feature và query
key, chờ history BRAM phát result_valid, sau đó ghép 19 history feature với
9 base feature mới gửi classifier. Vì vậy không dùng history cũ ở cycle close.

Phiên bản hiện hành dùng một slot close-event handshake. Khi nhiều flow đóng
liên tiếp trong lúc history query đang chạy, cờ close_event_overflow được đặt
thay vì im lặng báo kết quả sai. Để dùng resource profile trên traffic burst
thật cần làm tiếp FIFO close-event nhiều entry:

1. FIFO close-event chứa base feature và query key.
2. History engine lấy event khi rảnh, phát result_valid.
3. Ghép history result với base feature, rồi phát record classifier.
4. Counter overflow và testbench burst close-event.
5. So sánh output resource profile với reference và software.

Đây là ràng buộc kiến trúc, không chỉ là đổi kiểu reg sang RAM. Profile resource
đã là profile build trong Gowin project, nhưng chưa có FIFO close-event burst
và chưa có report PNR hoàn tất. Không được kết luận utilization cuối cùng trước
khi Gowin synthesis/P&R tạo report thành công.

## 10. Build, nạp bitstream và demo

Bước 1, kiểm tra RTL:

    cd ME\fpga\ip_final
    .\scripts\verify_ip_final.ps1

Bước 2, synthesis và PNR:

    .\build_and_program.ps1

Nếu Gowin build thành công, nạp release/ip_final.fs bằng Gowin Programmer.
Chỉ chọn external flash khi muốn boot persistent.

Bước 3, trình tự phần cứng:

1. Cắm RMII/RGMII, UART TTL và GND chung.
2. Kiểm tra cả hai PHY lên 100 Mb/s.
3. Nạp fs, xác nhận bridge ping/traffic hai chiều trước.
4. Trên laptop mở dashboard UART.
5. Upload đủ 1.273 node, kiểm tra model version đổi.
6. Bắt đầu traffic A sang B và quan sát dòng IDS.

Trên máy B, chạy trước:

    .\ME\fpga\ip_final\scripts\run_machine_b.ps1 -Expected 100

Trên laptop UART:

    python .\ME\fpga\ip_final\server\ids_web_server.py --port COM17

Sau đó trên máy A:

    .\ME\fpga\ip_final\scripts\run_machine_a.ps1 -Count 100 -RateMbps 1

Thay COM17, IP và tốc độ traffic theo mạng thật. Script A/B phải chạy tại đúng
máy có IP đã cấu hình; lỗi bind IP trên laptop phát triển không tự là lỗi FPGA.

## 11. Cách trình bày đúng khi bảo vệ

- RTL tree có parity 100% với golden software vectors.
- Accuracy 95.4775% là dataset test accuracy, không phải live accuracy.
- FPGA bridge traffic hai chiều, IDS monitor/classify chiều A sang B.
- Node image qua UART là model update của Decision Tree, không phải neural
  network weight matrix.
- Upload demo có XOR checksum và số node. Production cần ACK/NACK, retry,
  SHA-256/chữ ký, profile hash và xác thực server.
- Không khẳng định đã nạp board nếu chưa có release/ip_final.fs từ PNR và chưa
  thực hiện thao tác vật lý trên board.

## 12. Checklist demo

- [ ] verify RTL pass.
- [ ] Gowin PNR pass, kiểm tra BSRAM utilization.
- [ ] Nạp ip_final.fs thành công.
- [ ] Link LAN8720 và RTL8211F ở 100 Mb/s.
- [ ] Ping/traffic A sang B qua bridge thành công.
- [ ] UART dashboard kết nối.
- [ ] Upload đủ 1.273 node, version thay đổi.
- [ ] Traffic A sang B tạo event IDS.
- [ ] Nếu cần live accuracy, chạy labeled replay và đối chiếu FPGA với
      software/ground truth.

