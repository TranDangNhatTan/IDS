# IP Gowin cần tạo trước khi ghép IDS qua LAN

`ip_final_core` dùng RJ45 onboard của ACG525: PHY RTL8211F-CG giao tiếp
**RGMII 2.5 V**. Không tạo IP RMII, LAN8720, UART hoặc USB.

## PLL RGMII Gigabit (bắt buộc)

Mở `Tools` → `IP Core Generator` → `Clock` → `PLL`.

| Mục | Giá trị |
|---|---|
| Device | `GW5A-25`, version `B`, part `GW5A-LV25UG324C2/I1` |
| Language | Verilog |
| Create In | `ME/fpga/ip_final_core/src/ip/eth_rgmii_pll` |
| File / Module name | `eth_rgmii_pll` |
| CLKIN | `50 MHz` |
| Feedback | Internal |
| Enable Lock | bật |
| PLL Reset, Power Down, mDRP, SSC | tắt |

Tab `Clkout0`: enable, `125 MHz`, phase `0°`.

Tab `Clkout1`: enable, `125 MHz`, phase `90°`.

`clkout0` clock MAC/logic. `clkout1` được forward ra RGMII TX clock để đặt
cạnh clock giữa cửa sổ data TX. Nhấn **OK** và chọn **Yes** khi IDE hỏi thêm
file vào project.

Sau khi tạo, giữ nguyên toàn bộ file Verilog do Gowin sinh trong
`src/ip/eth_rgmii_pll/`. Gửi lại danh sách file và phần module declaration của
`eth_rgmii_pll.v`; bước kế tiếp sẽ nối đúng port generated IP.

## Không cần IP khác lúc này

- `ODDR`/`IDDR` RGMII dùng primitive Gowin trực tiếp trong RTL.
- Model 1,273 node × 64 bit dùng `DPB` BSRAM native, không dùng FF và không
  cần Memory IP Generator.
- UART/USB/RMII không thuộc kiến trúc LAN-only.

Luồng sau khi ghép PLL là:

`RGMII RX → UDP parser → model loader hoặc 28 features → Tree BRAM → UDP result TX`.
