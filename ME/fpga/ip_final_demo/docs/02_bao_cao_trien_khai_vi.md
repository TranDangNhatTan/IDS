# BÃ¡o cÃ¡o triá»ƒn khai IP Final â€“ FPGA IDS inline ACG525

## 1. Má»¥c tiÃªu demo

Há»‡ thá»‘ng minh há»a IDS cháº¡y trÃªn FPGA ACG525 á»Ÿ cháº¿ Ä‘á»™ inline monitor:
FPGA náº±m giá»¯a mÃ¡y A vÃ  mÃ¡y B Ä‘á»ƒ chuyá»ƒn tiáº¿p Ethernet hai chiá»u, Ä‘á»“ng thá»i
quan sÃ¡t lÆ°u lÆ°á»£ng Ä‘i tá»« A sang B vÃ  phÃ¢n loáº¡i báº±ng Decision Tree.

NguyÃªn táº¯c thiáº¿t káº¿ lÃ  Ethernet forwarding hoáº¡t Ä‘á»™ng Ä‘á»™c láº­p vá»›i IDS. Náº¿u model
chÆ°a náº¡p, Ä‘ang náº¡p model hoáº·c IDS cÃ³ lá»—i, bridge Ethernet váº«n tiáº¿p tá»¥c chuyá»ƒn
frame. IDS khÃ´ng Ä‘Æ°á»£c phÃ©p sá»Ÿ há»¯u hoáº·c cháº·n chÃ¢n TX Ethernet.

## 2. Kiáº¿n trÃºc váº­t lÃ½

    MÃ¡y A / router
           |
           | Ethernet 100 Mb/s
           v
    LAN8720 (RMII) <--> FPGA ACG525 <--> RTL8211F (RGMII) <--> MÃ¡y B / switch
                          |
                          | UART TTL 3.3 V, 115200, 8-N-1
                          v
                  Laptop / server web local

UART lÃ  TTL 3.3 V, khÃ´ng pháº£i RS-232. DÃ¢y theo constraint hiá»‡n táº¡i: FPGA V8
(TX) sang RX adapter, TX adapter sang FPGA V7 (RX), vÃ  GND chung. ChÃ¢n V7 pháº£i
Ä‘Æ°á»£c Ä‘á»‘i chiáº¿u vá»›i sÆ¡ Ä‘á»“ board thá»±c táº¿ trÆ°á»›c khi cáº¯m.

## 3. Luá»“ng dá»¯ liá»‡u Ethernet vÃ  IDS

    RMII RX
      |-- bridge Ä‘Ã£ kiá»ƒm chá»©ng --> RGMII TX --> MÃ¡y B
      |       (Ä‘Æ°á»ng chuyá»ƒn tiáº¿p khÃ´ng phá»¥ thuá»™c IDS)
      |
      '-- RMII deserializer monitor
              --> packet parser
                  --> flow table
                      --> history features
                          --> feature quantizer
                              --> Decision Tree
                                  --> UART telemetry

Top module lÃ  top_acg525_inline_ids.v. NÃ³ dÃ¹ng bridge
top_acg525_rgmii_rmii_bridge lÃ m chá»§ duy nháº¥t cá»§a cÃ¡c chÃ¢n TX Ethernet. Má»™t
RMII deserializer thá»© hai chá»‰ Ä‘á»c cÃ¹ng tÃ­n hiá»‡u RMII Ä‘á»ƒ monitor vÃ  khÃ´ng can
thiá»‡p forwarding. PhiÃªn báº£n hiá»‡n táº¡i classify chiá»u A sang B; chiá»u ngÆ°á»£c láº¡i
váº«n bridge nhÆ°ng chÆ°a classify.

## 4. Ná»™i dung thÆ° má»¥c IP final

    ME/fpga/ip_final/
    |-- src/
    |   |-- top_acg525_inline_ids.v       top board
    |   |-- model_update_uart.v           giao thá»©c náº¡p model
    |   |-- ids_tree_rom_banked.v         RAM model writable
    |   |-- ids_tree_engine_live.v        suy luáº­n Decision Tree
    |   |-- ids_packet_top_live.v         parser, flow, history, classifier
    |   |-- ids_uart_telemetry.v          log káº¿t quáº£ UART
    |   |-- ip_final.cst, ip_final.sdc    pin vÃ  timing constraint
    |   '-- deps/                         snapshot dependency RTL ná»™i bá»™
    |-- model/node_rom.mem                1.273 node Ä‘á»ƒ upload
    |-- server/ids_web_server.py          dashboard local vÃ  UART uploader
    |-- scripts/                          verify, traffic mÃ¡y A vÃ  B
    |-- tb/                               testbench
    |-- build_gowin.tcl, ip_final.gprj    project Gowin
    '-- docs/                             tÃ i liá»‡u

ToÃ n bá»™ RTL mÃ  project Gowin dÃ¹ng Ä‘Ã£ á»Ÿ src/deps hoáº·c src. Hai file project
khÃ´ng cÃ²n tham chiáº¿u RTL tá»« demo_connect hay ME/hw/rtl. Model image cÅ©ng náº±m
trong chÃ­nh ip_final.

## 5. Feature vÃ  Decision Tree

Packet parser trÃ­ch trÆ°á»ng L2/L3/L4. Flow table gom packet theo 5-tuple hai
chiá»u, theo dÃµi byte, thá»i gian, fragment vÃ  urgent flag. Khi TCP flow Ä‘Ã³ng
hoáº·c timeout, nÃ³ táº¡o raw record 28 feature:

1. ChÃ­n feature flow: duration, protocol, service, flag, source bytes,
   destination bytes, land, wrong fragment, urgent.
2. MÆ°á»i chÃ­n feature history theo host vÃ  service.

ids_feature_ingest lÆ°á»£ng tá»­ hÃ³a feature theo profile model. ids_tree_engine_live
duyá»‡t Decision Tree vÃ  xuáº¥t class_id, leaf_node, step_count, error_code.

Model dt_fpga_flow28_fixed cÃ³ káº¿t quáº£ software trÃªn táº­p test cÃ³ nhÃ£n:

| Chá»‰ sá»‘ | GiÃ¡ trá»‹ |
|---|---:|
| Accuracy test | 95.4775% |
| Macro F1 | 66.07% |
| Attack recall | 99.70% |
| False-positive rate | 6.30% |

CÃ¡c sá»‘ nÃ y chá»‰ lÃ  accuracy trÃªn dataset cÃ³ ground truth, khÃ´ng pháº£i accuracy
cá»§a traffic demo live khÃ´ng nhÃ£n.

## 6. Náº¡p model qua UART

Sau má»—i láº§n FPGA cáº¥u hÃ¬nh, model RAM trá»‘ng. Laptop/server pháº£i upload
model/node_rom.mem rá»“i activate model trÆ°á»›c khi IDS classify packet. Ethernet
forwarding váº«n hoáº¡t Ä‘á»™ng trong giai Ä‘oáº¡n nÃ y.

Giao thá»©c UART:

    Begin image: A5 5A 12 12
    Write node : A5 5A 10 addr_lo addr_hi data_byte_0 ... data_byte_7 XOR
    Activate   : A5 5A 11 11

- data byte 0 lÃ  bits 7:0 cá»§a node word 64-bit, little endian.
- Checksum lÃ  XOR cá»§a command vÃ  payload.
- FPGA chá»‰ activate khi nháº­n Ä‘á»§ 1.273 word.
- Frame checksum sai bá»‹ bá» vÃ  Ä‘áº·t cá» checksum_error.
- Trong update, classification bá»‹ gate Ä‘á»ƒ khÃ´ng Ä‘á»c node Ä‘ang thay Ä‘á»•i.

Server ids_web_server.py má»Ÿ dashboard táº¡i http://127.0.0.1:8080. NÃºt Upload
node_rom.mem gá»­i begin, toÃ n bá»™ write command, rá»“i activate.

## 7. UART telemetry

Má»—i inference hoÃ n táº¥t phÃ¡t má»™t dÃ²ng:

    IDS,<class_hex>,<leaf_hex>,<steps_hex>,<error>,<bank>,<version_hex>

Dashboard hiá»ƒn thá»‹ event, tá»•ng káº¿t quáº£, alert count, leaf, sá»‘ step vÃ  model
version. Dashboard chá»‰ Ä‘Æ°á»£c bÃ¡o prediction, event rate vÃ  metric váº­n hÃ nh.
KhÃ´ng Ä‘Æ°á»£c tá»± bÃ¡o live accuracy náº¿u chÆ°a replay traffic cÃ³ nhÃ£n Ä‘á»ƒ Ä‘á»‘i chiáº¿u.

## 8. Kiá»ƒm chá»©ng Ä‘Ã£ thá»±c hiá»‡n

| Kiá»ƒm tra | Káº¿t quáº£ | Ã nghÄ©a |
|---|---|---|
| Model, CSV, ROM parity | 147.674 giÃ¡ trá»‹ feature | Export mapping Ä‘Ãºng |
| Tree RTL parity | 22.156 / 22.156 vector | RTL khá»›p golden model |
| Model-update UART TB | MODEL_UPDATE_UART_PASS words=1273 | Giao thá»©c upload Ä‘Ãºng |
| BRAM history TB | HISTORY_BRAM_PASS cycles=8 time_count=2 | RAM tuáº§n tá»± Ä‘Ãºng |
| Local top elaboration | IP_FINAL_LOCAL_RTL_LINT_PASS | Local RTL compile qua top |

Tree RTL parity 100% cÃ³ nghÄ©a RTL khá»›p leaf/nhÃ£n golden do software táº¡o. NÃ³
khÃ´ng thay tháº¿ dataset accuracy 95.4775%.

Cháº¡y regression trÆ°á»›c build:

    cd ME\fpga\ip_final
    .\scripts\verify_ip_final.ps1

Káº¿t quáº£ cáº§n cÃ³ HISTORY_BRAM_PASS, MODEL_UPDATE_UART_PASS vÃ 
IP_FINAL_VERIFY_PASS.

## 9. Kiáº¿n trÃºc bá»™ nhá»› vÃ  tá»‘i Æ°u tÃ i nguyÃªn

### Model RAM

ids_tree_rom_banked.v dÃ¹ng primitive DPB trá»±c tiáº¿p cá»§a GW5A, khÃ´ng chá»‰ dÃ¹ng
ram_style = block. Model 1.273 x 64 bit Ä‘Æ°á»£c tá»• chá»©c thÃ nh hai bank 1.024 x
64 bit; má»—i bank 64-bit dÃ¹ng bá»‘n DPB 1.024 x 16 bit. Tá»•ng cá»™ng model chiáº¿m
8 macro BSRAM 16-Kbit. Port A ghi tá»« UART; port B Ä‘á»c cho tree engine.
RAM writable runtime vÃ  khÃ´ng dÃ¹ng readmemh, trÃ¡nh tool má»Ÿ rá»™ng RAM initialized
writable quÃ¡ lá»›n.

Sau PNR, utilization report pháº£i thá»ƒ hiá»‡n tá»‘i thiá»ƒu 8 BSRAM do tree model.
ÄÃ¢y lÃ  báº±ng chá»©ng macro Ä‘Ã£ Ä‘Æ°á»£c place. Attribute hoáº·c dÃ²ng log Extracting RAM
khÃ´ng cÃ²n lÃ  báº±ng chá»©ng Ä‘á»§.

### Flow table

ids_flow_table cÃ³ 16 entry vÃ  lookup fully-associative má»™t chu ká»³. NÃ³ chá»‰ vÃ i
Kbit nhÆ°ng pháº£i so sÃ¡nh song song. Giá»¯ nÃ³ thÃ nh register/LUT há»£p lÃ½ hÆ¡n Ã©p vÃ o
má»™t block RAM 16-Kbit, vá»‘n lÃ£ng phÃ­ vÃ  lÃ m máº¥t lookup má»™t chu ká»³.

### History window

ids_history_window.v lÃ  functional reference, scan 256 entry song song Ä‘á»ƒ
tráº£ history trong cycle flow Ä‘Ã³ng. NÃ³ phÃ¹ há»£p simulation/parity, khÃ´ng phÃ¹ há»£p
má»™t BRAM má»™t cá»•ng.

src/deps/ids_history_window_bram.v pack entry 92-bit vÃ o RAM block, Ä‘á»c má»™t
entry má»—i chu ká»³. Query depth 256 máº¥t 2 x 256 + 1 = 513 chu ká»³; vá»›i clock
50 MHz lÃ  khoáº£ng 10.26 microsecond/query.

Profile Gowin hiá»‡n dÃ¹ng ids_packet_top_resource, ids_flow_table_resource vÃ 
ids_history_pipeline_resource; nÃ³ khÃ´ng cÃ²n dÃ¹ng ids_history_window.v hoáº·c
ids_flow_table.v reference. Khi flow Ä‘Ã³ng, pipeline giá»¯ base feature vÃ  query
key, chá» history BRAM phÃ¡t result_valid, sau Ä‘Ã³ ghÃ©p 19 history feature vá»›i
9 base feature má»›i gá»­i classifier. VÃ¬ váº­y khÃ´ng dÃ¹ng history cÅ© á»Ÿ cycle close.

PhiÃªn báº£n hiá»‡n hÃ nh dÃ¹ng má»™t slot close-event handshake. Khi nhiá»u flow Ä‘Ã³ng
liÃªn tiáº¿p trong lÃºc history query Ä‘ang cháº¡y, cá» close_event_overflow Ä‘Æ°á»£c Ä‘áº·t
thay vÃ¬ im láº·ng bÃ¡o káº¿t quáº£ sai. Äá»ƒ dÃ¹ng resource profile trÃªn traffic burst
tháº­t cáº§n lÃ m tiáº¿p FIFO close-event nhiá»u entry:

1. FIFO close-event chá»©a base feature vÃ  query key.
2. History engine láº¥y event khi ráº£nh, phÃ¡t result_valid.
3. GhÃ©p history result vá»›i base feature, rá»“i phÃ¡t record classifier.
4. Counter overflow vÃ  testbench burst close-event.
5. So sÃ¡nh output resource profile vá»›i reference vÃ  software.

ÄÃ¢y lÃ  rÃ ng buá»™c kiáº¿n trÃºc, khÃ´ng chá»‰ lÃ  Ä‘á»•i kiá»ƒu reg sang RAM. Profile resource
Ä‘Ã£ lÃ  profile build trong Gowin project, nhÆ°ng chÆ°a cÃ³ FIFO close-event burst
vÃ  chÆ°a cÃ³ report PNR hoÃ n táº¥t. KhÃ´ng Ä‘Æ°á»£c káº¿t luáº­n utilization cuá»‘i cÃ¹ng trÆ°á»›c
khi Gowin synthesis/P&R táº¡o report thÃ nh cÃ´ng.

## 10. Build, náº¡p bitstream vÃ  demo

BÆ°á»›c 1, kiá»ƒm tra RTL:

    cd ME\fpga\ip_final
    .\scripts\verify_ip_final.ps1

BÆ°á»›c 2, synthesis vÃ  PNR:

    .\build_and_program.ps1

Náº¿u Gowin build thÃ nh cÃ´ng, náº¡p release/ip_final.fs báº±ng Gowin Programmer.
Chá»‰ chá»n external flash khi muá»‘n boot persistent.

BÆ°á»›c 3, trÃ¬nh tá»± pháº§n cá»©ng:

1. Cáº¯m RMII/RGMII, UART TTL vÃ  GND chung.
2. Kiá»ƒm tra cáº£ hai PHY lÃªn 100 Mb/s.
3. Náº¡p fs, xÃ¡c nháº­n bridge ping/traffic hai chiá»u trÆ°á»›c.
4. TrÃªn laptop má»Ÿ dashboard UART.
5. Upload Ä‘á»§ 1.273 node, kiá»ƒm tra model version Ä‘á»•i.
6. Báº¯t Ä‘áº§u traffic A sang B vÃ  quan sÃ¡t dÃ²ng IDS.

TrÃªn mÃ¡y B, cháº¡y trÆ°á»›c:

    .\ME\fpga\ip_final\scripts\run_machine_b.ps1 -Expected 100

TrÃªn laptop UART:

    python .\ME\fpga\ip_final\server\ids_web_server.py --port COM17

Sau Ä‘Ã³ trÃªn mÃ¡y A:

    .\ME\fpga\ip_final\scripts\run_machine_a.ps1 -Count 100 -RateMbps 1

Thay COM17, IP vÃ  tá»‘c Ä‘á»™ traffic theo máº¡ng tháº­t. Script A/B pháº£i cháº¡y táº¡i Ä‘Ãºng
mÃ¡y cÃ³ IP Ä‘Ã£ cáº¥u hÃ¬nh; lá»—i bind IP trÃªn laptop phÃ¡t triá»ƒn khÃ´ng tá»± lÃ  lá»—i FPGA.

## 11. CÃ¡ch trÃ¬nh bÃ y Ä‘Ãºng khi báº£o vá»‡

- RTL tree cÃ³ parity 100% vá»›i golden software vectors.
- Accuracy 95.4775% lÃ  dataset test accuracy, khÃ´ng pháº£i live accuracy.
- FPGA bridge traffic hai chiá»u, IDS monitor/classify chiá»u A sang B.
- Node image qua UART lÃ  model update cá»§a Decision Tree, khÃ´ng pháº£i neural
  network weight matrix.
- Upload demo cÃ³ XOR checksum vÃ  sá»‘ node. Production cáº§n ACK/NACK, retry,
  SHA-256/chá»¯ kÃ½, profile hash vÃ  xÃ¡c thá»±c server.
- KhÃ´ng kháº³ng Ä‘á»‹nh Ä‘Ã£ náº¡p board náº¿u chÆ°a cÃ³ release/ip_final.fs tá»« PNR vÃ  chÆ°a
  thá»±c hiá»‡n thao tÃ¡c váº­t lÃ½ trÃªn board.

## 12. Checklist demo

- [ ] verify RTL pass.
- [ ] Gowin PNR pass, kiá»ƒm tra BSRAM utilization.
- [ ] Náº¡p ip_final.fs thÃ nh cÃ´ng.
- [ ] Link LAN8720 vÃ  RTL8211F á»Ÿ 100 Mb/s.
- [ ] Ping/traffic A sang B qua bridge thÃ nh cÃ´ng.
- [ ] UART dashboard káº¿t ná»‘i.
- [ ] Upload Ä‘á»§ 1.273 node, version thay Ä‘á»•i.
- [ ] Traffic A sang B táº¡o event IDS.
- [ ] Náº¿u cáº§n live accuracy, cháº¡y labeled replay vÃ  Ä‘á»‘i chiáº¿u FPGA vá»›i
      software/ground truth.


