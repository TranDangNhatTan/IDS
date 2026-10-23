`timescale 1ns/1ps
// Hardware-only RTL8211F link diagnostic for the ACG525 onboard RJ45.
// No UDP, MAC, RGMII TX or PLL is present here.  The PHY reset output is held
// low for 100 ms after configuration, then driven high permanently.
module top_phy_link_diag(
 input wire sys_clk_50,
 input wire eth_rgmii_rx_clk,
 input wire [3:0] eth_rgmii_rxd,
 input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,
 output wire [3:0] eth_rgmii_txd,
 output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,
 output wire eth_mdc,
 inout wire eth_mdio,
 output wire [3:0] led
);
 localparam integer PHY_RESET_CYCLES = 5_000_000; // 100 ms at 50 MHz
 reg [22:0] reset_count = 23'd0;
 reg phy_reset_released = 1'b0;
 reg [25:0] blink_count = 26'd0;

 always @(posedge sys_clk_50) begin
   blink_count <= blink_count + 1'b1;
   if (!phy_reset_released) begin
     if (reset_count == PHY_RESET_CYCLES - 1)
       phy_reset_released <= 1'b1;
     else
       reset_count <= reset_count + 1'b1;
   end
 end

 assign eth_rst_n = phy_reset_released;
 assign eth_mdc = 1'b0;
 assign eth_mdio = 1'bz;
 assign eth_rgmii_tx_clk = 1'b0;
 assign eth_rgmii_txd = 4'b0000;
 assign eth_rgmii_tx_ctl = 1'b0;

 // All four physical LEDs must blink after reset release, at visibly
 // different rates.  This proves the programmed image and LED CTS mapping.
 assign led[0] = blink_count[25];
 assign led[1] = phy_reset_released ? blink_count[24] : 1'b0;
 assign led[2] = phy_reset_released ? blink_count[23] : 1'b0;
 assign led[3] = phy_reset_released ? blink_count[22] : 1'b0;
endmodule
