`timescale 1ns/1ps
// Safe RTL8211F address-discovery image. RGMII TX is held idle throughout.
module top_acg525_phy_mdio_scan_diag(
 input wire sys_clk_50,input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire [3:0] led
);
 localparam integer RESET_CYCLES=5_000_000;
 reg [22:0] reset_count=0;reg reset_done=0;reg [25:0] heartbeat=0;
 always @(posedge sys_clk_50) begin
  heartbeat<=heartbeat+1'b1;
  if(!reset_done) begin if(reset_count==RESET_CYCLES-1) reset_done<=1;else reset_count<=reset_count+1'b1;end
 end
 wire mdio_out,mdio_oe,scan_done,phy_found;wire [4:0] found_addr;wire [15:0] found_id1;
 rtl8211f_mdio_scan scanner(.clk(sys_clk_50),.rst_n(reset_done),.mdio_in(eth_mdio),.mdc(eth_mdc),.mdio_out(mdio_out),.mdio_oe(mdio_oe),.scan_done(scan_done),.phy_found(phy_found),.found_addr(found_addr),.found_id1(found_id1));
 assign eth_rst_n=reset_done;assign eth_mdio=mdio_oe?mdio_out:1'bz;
 assign eth_rgmii_tx_clk=1'b0;assign eth_rgmii_txd=4'b0;assign eth_rgmii_tx_ctl=1'b0;
 // D0=heartbeat; D1=reset released; D2=scan complete; D3=a real PHY replied.
 assign led={phy_found&heartbeat[25],scan_done&heartbeat[25],reset_done&heartbeat[25],heartbeat[25]};
endmodule
