`timescale 1ns/1ps
// Controlled PHY configuration diagnostic.
// It uses the same 100 ms reset, Gowin PLL and MDIO sequence as the UDP core,
// but keeps the RGMII TX interface electrically idle.  Thus an Ethernet link
// result proves (or disproves) MDIO speed configuration independently of the
// 25 MHz TX clock/data path.
module top_acg525_phy_mdio_diag(
 input wire sys_clk_50,
 input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire [3:0] led
);
 top_acg525_udp_echo #(
   .ENABLE_MDIO_CONFIG(1),
   .ENABLE_TX_INTERFACE(0),
   .PHY_ADDR(5'b00010)
 ) core (
   .sys_clk_50(sys_clk_50),
   .eth_rgmii_rx_clk(eth_rgmii_rx_clk),.eth_rgmii_rxd(eth_rgmii_rxd),.eth_rgmii_rx_ctl(eth_rgmii_rx_ctl),
   .eth_rgmii_tx_clk(eth_rgmii_tx_clk),.eth_rgmii_txd(eth_rgmii_txd),.eth_rgmii_tx_ctl(eth_rgmii_tx_ctl),
   .eth_rst_n(eth_rst_n),.eth_mdc(eth_mdc),.eth_mdio(eth_mdio),.led(led)
 );
endmodule
