# IP Final Demo

Gowin project độc lập cho ACG525 inline IDS, dùng resource profile:

- Decision Tree: 8 macro GW5A DPB (BRAM) để chứa 1.273 node UART-updatable.
- History: RAM tuần tự (không còn scan 256 entry combinational).
- Flow close -> history handshake -> classifier.
- UART log và laptop web server.

Chạy kiểm tra trước synthesis:

    .\scripts\verify_ip_final_demo.ps1

Mở file ip_final_demo.gprj bằng Gowin IDE hoặc chạy:

    .\build_and_program.ps1

Tài liệu: docs/02_bao_cao_trien_khai_vi.md.

