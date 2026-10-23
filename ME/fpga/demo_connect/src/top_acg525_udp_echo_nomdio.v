`timescale 1ns/1ps
// Link-isolation image: normal UDP/RGMII core but leaves RTL8211F MDIO
// untouched, so its hardware strap/autonegotiation settings remain active.
module top_acg525_udp_echo_nomdio(
 input wire sys_clk_50,
 input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire [3:0] led
);
 // Keep RGMII TX clock off in this image: without MDIO configuration the
 // PHY defaults to Gigabit and a 25 MHz TX clock would be invalid.
 top_acg525_udp_echo #(.ENABLE_MDIO_CONFIG(0),.ENABLE_TX_INTERFACE(0)) core(
  .sys_clk_50(sys_clk_50),.eth_rgmii_rx_clk(eth_rgmii_rx_clk),.eth_rgmii_rxd(eth_rgmii_rxd),.eth_rgmii_rx_ctl(eth_rgmii_rx_ctl),
  .eth_rgmii_tx_clk(eth_rgmii_tx_clk),.eth_rgmii_txd(eth_rgmii_txd),.eth_rgmii_tx_ctl(eth_rgmii_tx_ctl),
  .eth_rst_n(eth_rst_n),.eth_mdc(eth_mdc),.eth_mdio(eth_mdio),.led(led));
endmodule
