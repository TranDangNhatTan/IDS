`timescale 1ns/1ps
// UDP echo bring-up for the ACG525 onboard RTL8211F RGMII PHY.
module top_acg525_udp_echo #(
 // RTL8211F needs a conservative reset release interval on this board.
 // 5,000,000 cycles at 50 MHz = 100 ms; the proven PHY diagnostic uses the
 // same timing and obtains a physical link.
 parameter integer POR_CYCLES=5000000,
 parameter integer RX_CLOCK_PROBE_BIT=20,
 parameter integer HEARTBEAT_BIT=25,
 // MDIO must not start immediately after nRESET rises.  The PHY diagnostic
 // proves the copper link needs time to stabilize; wait a conservative 1 s.
 parameter integer MDIO_START_DELAY=50000000,
 parameter integer ENABLE_MDIO_CONFIG=1,
 parameter integer ENABLE_TX_INTERFACE=1,
 // RTL8211F PHYAD[2:0] straps on the ACG525 schematic are 010.
 parameter [4:0] PHY_ADDR=5'b00010
)(
 input wire sys_clk_50,
 input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire [3:0] led
);
 reg [22:0] por_count=0;reg por_done=0;
 always @(posedge sys_clk_50) begin
  if(!por_done) begin if(por_count==POR_CYCLES-1) por_done<=1;else por_count<=por_count+1'b1;end
 end
 wire logic_rst_n=por_done;assign eth_rst_n=por_done;
 reg [25:0] heartbeat=0;always @(posedge sys_clk_50) heartbeat<=heartbeat+1'b1;

 // Force the onboard PHY to 100BASE-TX full duplex to match these proven
 // 25 MHz RGMII adapters.
 wire mdio_done;
 generate if (ENABLE_MDIO_CONFIG != 0) begin : g_mdio_config
  wire mdio_out,mdio_oe;
  rtl8211f_mdio_init #(.START_DELAY(MDIO_START_DELAY),.PHY_ADDR(PHY_ADDR)) mdio_init(
   .clk(sys_clk_50),.rst_n(logic_rst_n),.mdc(eth_mdc),.mdio_out(mdio_out),.mdio_oe(mdio_oe),.init_done(mdio_done));
  assign eth_mdio=mdio_oe?mdio_out:1'bz;
 end else begin : g_no_mdio_config
  assign eth_mdc=1'b0;
  assign eth_mdio=1'bz;
  assign mdio_done=logic_rst_n;
 end endgenerate

 // A dedicated GW5A PLLG generates the 25 MHz RGMII transmit clock.  There
 // is no fabric clock divider on this clock path.
 wire tx_clk_25m, pll_lock;
 gowin_pll_50m_to_25m tx_pll(.clk_in(sys_clk_50),.reset(!logic_rst_n),.clk_25m(tx_clk_25m),.lock(pll_lock));
 // Before MDIO has disabled Gigabit advertisement, the PHY may be in its
 // default 1000BASE-T mode and therefore expects a 125 MHz RGMII TX clock.
 // Do not present the 25 MHz 100BASE-TX clock until the 100 Mb/s MDIO setup
 // has been sent.  This avoids invalid 25 MHz clocking during auto-negotiation.
 wire tx_interface_enable = logic_rst_n && pll_lock && mdio_done && (ENABLE_TX_INTERFACE != 0);
 assign eth_rgmii_tx_clk = tx_interface_enable ? tx_clk_25m : 1'b0;

 wire [7:0] phy_byte;wire phy_valid,phy_last,phy_error;
 rgmii_100_deserializer rx_phy(
  .rx_clk(eth_rgmii_rx_clk),.rst_n(logic_rst_n),.rxd(eth_rgmii_rxd),.rx_ctl(eth_rgmii_rx_ctl),
  .rx_byte(phy_byte),.rx_byte_valid(phy_valid),.rx_byte_last(phy_last),.rx_frame_error(phy_error));
 wire [7:0] rx_byte;wire rx_valid,rx_sop;
 rgmii_frame_adapter strip(
  .clk(eth_rgmii_rx_clk),.rst_n(logic_rst_n),.rx_byte(phy_byte),.rx_valid(phy_valid),.rx_last(phy_last),.rx_error(phy_error),
  .byte_data(rx_byte),.byte_valid(rx_valid),.byte_sop(rx_sop));
 wire ping_valid,peer_valid,ping_seen;wire [31:0] ping_seq,peer_ip;wire [47:0] peer_mac;wire [15:0] peer_port;
 udp_ping_rx parser(
  .clk(eth_rgmii_rx_clk),.rst_n(logic_rst_n),.byte_data(rx_byte),.byte_valid(rx_valid),.byte_sop(rx_sop),
  .ping_valid(ping_valid),.ping_sequence(ping_seq),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid),.rx_seen(ping_seen));

 // The request toggle and its stable payload are synchronized inside the
 // 25 MHz PLL TX domain by the transmitter.
 reg request_toggle_rx=0;
 always @(posedge eth_rgmii_rx_clk or negedge logic_rst_n)
  if(!logic_rst_n) request_toggle_rx<=0;else if(ping_valid&&peer_valid) request_toggle_rx<=~request_toggle_rx;
 wire frame_sent;
 rgmii_100_ack_tx_pll tx_phy(
  .tx_clk(tx_clk_25m),.rst_n(tx_interface_enable),.request_toggle(request_toggle_rx),.seq_in(ping_seq),
  .peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.txd(eth_rgmii_txd),.tx_ctl(eth_rgmii_tx_ctl),.frame_sent(frame_sent));

 // Bring-up LEDs: heartbeat, PHY reset released, actual Gowin PLL lock, and
 // MDIO sequence completion.  They do not depend on an Ethernet packet and
 // expose the critical hardware prerequisites directly on the board.
 reg [20:0] rx_clock_counter=0;reg raw_rx_seen=0;
 always @(posedge eth_rgmii_rx_clk or negedge logic_rst_n) begin
  if(!logic_rst_n) begin rx_clock_counter<=0;raw_rx_seen<=0;end
  else begin rx_clock_counter<=rx_clock_counter+1'b1;if(eth_rgmii_rx_ctl)raw_rx_seen<=1;end
 end
 reg clock_s1=0,clock_s2=0,clock_prev=0,rx_clock_seen=0;
 reg raw_s1=0,raw_s2=0,ping_s1=0,ping_s2=0;
 always @(posedge sys_clk_50 or negedge logic_rst_n) begin
  if(!logic_rst_n) begin clock_s1<=0;clock_s2<=0;clock_prev<=0;rx_clock_seen<=0;raw_s1<=0;raw_s2<=0;ping_s1<=0;ping_s2<=0;end
  else begin
   clock_s1<=rx_clock_counter[RX_CLOCK_PROBE_BIT];clock_s2<=clock_s1;clock_prev<=clock_s2;
   if(clock_s2!=clock_prev)rx_clock_seen<=1;
   raw_s1<=raw_rx_seen;raw_s2<=raw_s1;ping_s1<=ping_seen;ping_s2<=ping_s1;
  end
 end
 // A valid status blinks with LED0. This remains observable on either an
 // active-high or active-low LED transistor stage; an absent status is static.
 assign led={mdio_done&heartbeat[HEARTBEAT_BIT],pll_lock&heartbeat[HEARTBEAT_BIT],por_done&heartbeat[HEARTBEAT_BIT],heartbeat[HEARTBEAT_BIT]};
endmodule
