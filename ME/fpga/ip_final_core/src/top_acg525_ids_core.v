`timescale 1ns/1ps
// ACG525 onboard RTL8211F RGMII IDS demonstrator.
// UDP/IPv4 payloads: MOD1 model upload -> ACK1, FTR2 feature vector -> IDS1.
module top_acg525_ids_core(
 input wire sys_clk_50,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,input wire eth_rgmii_rx_clk,
 output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,output wire eth_rgmii_tx_clk,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire uart_tx,output wire [3:0] led
);
 localparam integer PHY_RESET_CYCLES=5_000_000;
 reg [22:0] reset_count=0; reg phy_reset_released=0; reg [25:0] heartbeat=0;
 always @(posedge sys_clk_50) begin
  heartbeat<=heartbeat+1'b1;
  if(!phy_reset_released) begin if(reset_count==PHY_RESET_CYCLES-1) phy_reset_released<=1'b1; else reset_count<=reset_count+1'b1; end
 end
 // 100BASE-TX RGMII: both generated clocks are 25 MHz.  The recovered PHY
 // RX clock is also 25 MHz after a 100 Mbps link has negotiated.
 wire pll_clk_25,pll_txclk_25,pll_lock;
 eth_rgmii_pll u_eth_rgmii_pll(.clkin(sys_clk_50),.clkout0(pll_clk_25),.clkout1(pll_txclk_25),.lock(pll_lock),.mdclk(sys_clk_50));
 wire core_rst_n=phy_reset_released&pll_lock;
 // The proven 100BASE-TX interface changes TXD/TX_CTL just after the rising
 // edge and lets the PHY sample them on the falling edge of this same 25 MHz
 // clock.  A separately phase-shifted clock moved the PHY sampling edge out
 // of that half-cycle data eye and produced locally completed but unreadable
 // ACK frames.
 assign eth_rst_n=phy_reset_released; assign eth_rgmii_tx_clk=core_rst_n ? pll_clk_25 : 1'b0;
 assign eth_mdc=1'b0; assign eth_mdio=1'bz;

 // RGMII is source-synchronous: consume RXD/RX_CTL in the recovered 25 MHz
 // PHY clock domain.  Sampling it with the unrelated 50 MHz oscillator is
 // only 2x oversampling and was proven on hardware to miss deterministic
 // edges; the PHY-provided clock is the authoritative sampling reference.
 wire rx_clk_aligned=eth_rgmii_rx_clk;

 wire [7:0] rx_byte; wire rx_valid,rx_sop,rx_last,rx_frame_error;
 rgmii_rx_byte rx_ddr(.rx_clk(rx_clk_aligned),.rst_n(core_rst_n),.sample_ce(1'b1),.rxd(eth_rgmii_rxd),.rx_ctl(eth_rgmii_rx_ctl),.byte_data(rx_byte),.byte_valid(rx_valid),.byte_sop(rx_sop),.byte_last(rx_last),.frame_error(rx_frame_error));
 wire raw_valid,raw_ready,engine_busy; wire [28*32-1:0] raw_features_flat; wire [31:0] record_sequence,accepted_records,dropped_records;
 wire parser_frame_error,udp_seen,model_write_en,model_activate,model_ready,model_ack; wire [11:0] model_write_addr; wire [63:0] model_write_data; wire [15:0] accepted_words;
 // Do not accept another FTR2 while the current tree walk is active, and do
 // not run inference until a complete model has been committed.
 wire parser_accept_ready=raw_ready && !engine_busy && model_ready;
 wire [47:0] peer_mac; wire [31:0] peer_ip; wire [15:0] peer_port; wire peer_valid;
 wire [31:0] trace_frames,trace_ipv4,trace_ip_udp,trace_dst_port,trace_magic,trace_hdr0,trace_hdr1,trace_hdr2;
 // Counts PHY RX_CTL at the package pin.  Declared before UART/trace users
 // so it is never inferred as an accidental one-bit implicit wire.
 reg [31:0] raw_rgmii_cycles;
 reg rxclk_s1,rxclk_s2,rxclk_prev,rx_clock_seen,rxctl_s1,rxctl_s2,txseen_s1,txseen_s2;
 reg txvalid_s1,txvalid_s2,replyseen_s1,replyseen_s2,replytog_s1,replytog_s2;
 reg tx_seen,tx_started;
 // One-shot capture of the first 24 raw RGMII nibbles. This remains frozen
 // until reconfiguration so UART can reveal pin order/phase without an ILA.
 reg [95:0] raw_nibble_snapshot;
 reg [4:0] raw_nibble_count;
 ids_udp_feature_rx rx_protocol(
  .clk(rx_clk_aligned),.rst_n(core_rst_n),.rx_data(rx_byte),.rx_valid(rx_valid),.rx_sop(rx_sop),.engine_busy(engine_busy),.raw_ready(parser_accept_ready),
  .raw_valid(raw_valid),.raw_features_flat(raw_features_flat),.record_sequence(record_sequence),.accepted_records(accepted_records),.dropped_records(dropped_records),.frame_error(parser_frame_error),.udp_seen(udp_seen),
  .model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),.model_ready(model_ready),.accepted_words(accepted_words),.model_ack(model_ack),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid),
  .trace_frames(trace_frames),.trace_ipv4(trace_ipv4),.trace_ip_udp(trace_ip_udp),.trace_dst_port(trace_dst_port),.trace_magic(trace_magic),.trace_hdr0(trace_hdr0),.trace_hdr1(trace_hdr1),.trace_hdr2(trace_hdr2));
 wire done,result_valid,active_bank; wire [5:0] class_id; wire [11:0] leaf_node; wire [2:0] error_code; wire [7:0] step_count; wire [15:0] model_version;
 ids_top_live ids_core(
  .clk(rx_clk_aligned),.rst_n(core_rst_n),.raw_record_valid(raw_valid&&model_ready),.raw_record_ready(raw_ready),.raw_features_flat(raw_features_flat),.model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),
  .busy(engine_busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version));

 // Retain the final observed model-BRAM write.  This is deliberately exposed
 // to UART so a physical upload can be proved without trusting web counters.
 reg [11:0] uart_last_write_addr; reg [15:0] uart_last_write_low;
 always @(posedge rx_clk_aligned or negedge core_rst_n)
  if(!core_rst_n) begin uart_last_write_addr<=0;uart_last_write_low<=0;end
  else if(model_write_en) begin uart_last_write_addr<=model_write_addr;uart_last_write_low<=model_write_data[15:0];end

 // Board USB-UART TX is V8, 115200 8-N-1.  It is independent from LAN TX.
 // PuTTY lines report parser stages, BRAM write count/address and state.
 ids_uart_trace uart_trace(.clk(sys_clk_50),.rst_n(core_rst_n),
  .frames(trace_frames),.ipv4(trace_ipv4),.ip_udp(trace_ip_udp),.dst_port(trace_dst_port),.magic(trace_magic),.accepted_words(accepted_words),
  .header0(trace_hdr0),.header1(trace_hdr1),.header2(trace_hdr2),.raw_rx_ctl_cycles(raw_rgmii_cycles),
  .raw_nibbles(raw_nibble_snapshot),.raw_nibble_count({rx_clock_seen,txseen_s2,txvalid_s2,replyseen_s2,replytog_s2}),
  .last_write_addr(uart_last_write_addr),.last_write_low(uart_last_write_low),.model_ready(model_ready),.parser_error(parser_frame_error),.uart_tx(uart_tx));

 // One-entry result mailbox: source values remain stable until the next
 // dashboard request; the toggle is synchronized to the TX PLL clock.
 reg reply_toggle,reply_is_ack,reply_peer_valid; reg [31:0] reply_seq,reply_peer_ip,reply_accepted,reply_dropped,inflight_sequence; reg [47:0] reply_peer_mac; reg [15:0] reply_peer_port,reply_words,reply_version; reg [5:0] reply_class; reg [11:0] reply_leaf; reg [7:0] reply_steps; reg [2:0] reply_error; reg reply_ready;
 always @(posedge rx_clk_aligned or negedge core_rst_n) begin
  if(!core_rst_n) begin reply_toggle<=0;reply_is_ack<=0;reply_peer_valid<=0;reply_seq<=0;reply_peer_ip<=0;reply_peer_mac<=0;reply_peer_port<=0;reply_words<=0;reply_version<=0;reply_class<=0;reply_leaf<=0;reply_steps<=0;reply_error<=0;reply_ready<=0;reply_accepted<=0;reply_dropped<=0;inflight_sequence<=0;end
  else begin
   if(raw_valid&&parser_accept_ready) inflight_sequence<=record_sequence;
   if(model_ack||result_valid) begin
    reply_toggle<=~reply_toggle;reply_is_ack<=model_ack;reply_peer_valid<=peer_valid;reply_seq<=model_ack?record_sequence:inflight_sequence;reply_peer_ip<=peer_ip;reply_peer_mac<=peer_mac;reply_peer_port<=peer_port;reply_words<=accepted_words;reply_version<=model_version;reply_class<=class_id;reply_leaf<=leaf_node;reply_steps<=step_count;reply_error<=error_code;reply_ready<=model_ready;reply_accepted<=accepted_records;reply_dropped<=dropped_records;
   end
  end
 end
 reg reply_sync1,reply_sync2;
 // Reply FSM and the forwarded 100M clock intentionally use the same PLL
 // output; rgmii_tx_byte updates the pins after the rising edge and provides
 // nearly half a 25 MHz period of setup before the PHY's falling sample edge.
 always @(posedge pll_clk_25 or negedge core_rst_n) if(!core_rst_n) begin reply_sync1<=0;reply_sync2<=0;end else begin reply_sync1<=reply_toggle;reply_sync2<=reply_sync1;end
 wire [7:0] reply_tx_byte; wire reply_tx_valid,tx_byte_ready,tx_result_sent,tx_error;
 ids_udp_reply_tx reply_protocol(
  // A reply toggle is generated only after the RX parser has accepted a
  // protocol packet and latched the peer mailbox.  Do not gate that event
  // again with reply_peer_valid here: that single RX-domain bit is not part
  // of the toggle synchronizer and could make the TX FSM consume the event
  // without emitting a frame.
  .clk(pll_clk_25),.rst_n(core_rst_n),.peer_valid(1'b1),.peer_mac(reply_peer_mac),.peer_ip(reply_peer_ip),.peer_port(reply_peer_port),.reply_toggle(reply_sync2),.reply_is_ack(reply_is_ack),.record_sequence(reply_seq),.class_id(reply_class),.leaf_node(reply_leaf),.step_count(reply_steps),.error_code(reply_error),.model_version(reply_version),.model_ready(reply_ready),.accepted_words(reply_words),.accepted_records(reply_accepted),.dropped_records(reply_dropped),.tx_byte(reply_tx_byte),.tx_byte_valid(reply_tx_valid),.tx_byte_ready(tx_byte_ready),.result_sent(tx_result_sent),.tx_error(tx_error));
 // ACK1/IDS1 owns the serializer exclusively.  An older diagnostic sender
 // shared tx_byte_ready with this FSM; while its bytes were selected the reply
 // FSM still advanced, silently deleting ACK bytes and occasionally joining
 // two Ethernet frames.  Receive diagnostics remain available on UART.
 rgmii_tx_byte tx_ddr(.clk(pll_clk_25),.rst_n(core_rst_n),.byte_data(reply_tx_byte),.byte_valid(reply_tx_valid),.byte_ready(tx_byte_ready),.txd(eth_rgmii_txd),.tx_ctl(eth_rgmii_tx_ctl));
 always @(posedge pll_clk_25 or negedge core_rst_n)
  if(!core_rst_n) begin tx_seen<=0;tx_started<=0;end
  else begin if(reply_tx_valid)tx_started<=1;if(tx_result_sent)tx_seen<=1;end
 // Bring-up diagnostics persist until reconfiguration. RX_CTL is observed
 // directly in the recovered PHY clock domain, before the DDR/parser logic.
 reg raw_rgmii_seen; reg [20:0] rx_clock_counter;
 always @(posedge eth_rgmii_rx_clk or negedge core_rst_n)
  if(!core_rst_n) begin raw_rgmii_seen<=0;rx_clock_counter<=0;raw_nibble_snapshot<=0;raw_nibble_count<=0;end
  else if(eth_rgmii_rx_ctl) begin
   raw_rgmii_seen<=1;rx_clock_counter<=rx_clock_counter+1'b1;
   if(raw_nibble_count<5'd24) begin
    raw_nibble_snapshot<={raw_nibble_snapshot[91:0],eth_rgmii_rxd};
    raw_nibble_count<=raw_nibble_count+1'b1;
   end
  end else rx_clock_counter<=rx_clock_counter+1'b1;
 // Independent 50 MHz pin probe. C[4]=1 means recovered RX_CLK is alive;
 // X=1 means RX_CTL was observed without relying on that recovered clock.
 always @(posedge sys_clk_50 or negedge core_rst_n)
  if(!core_rst_n) begin rxclk_s1<=0;rxclk_s2<=0;rxclk_prev<=0;rx_clock_seen<=0;rxctl_s1<=0;rxctl_s2<=0;txseen_s1<=0;txseen_s2<=0;txvalid_s1<=0;txvalid_s2<=0;replyseen_s1<=0;replyseen_s2<=0;replytog_s1<=0;replytog_s2<=0;raw_rgmii_cycles<=0;end
  else begin
   rxclk_s1<=rx_clock_counter[20];rxclk_s2<=rxclk_s1;rxclk_prev<=rxclk_s2;
   if(rxclk_s2!=rxclk_prev)rx_clock_seen<=1;
   rxctl_s1<=eth_rgmii_rx_ctl;rxctl_s2<=rxctl_s1;
   txseen_s1<=tx_seen;txseen_s2<=txseen_s1;
   txvalid_s1<=tx_started;txvalid_s2<=txvalid_s1;
   replyseen_s1<=reply_sync2;replyseen_s2<=replyseen_s1;
   replytog_s1<=reply_toggle;replytog_s2<=replytog_s1;
   if(rxctl_s2)raw_rgmii_cycles<=raw_rgmii_cycles+1'b1;
  end
 // D2 is the physical RX indication.  It must not depend on IDDR/parser
 // bring-up: a lit D2 proves the RTL8211F asserted RX_CTL at the FPGA pin.
 // Byte/parser progress is reported precisely by DBG2 diagnostics instead.
 reg mac_byte_seen;
 always @(posedge rx_clk_aligned or negedge core_rst_n)
  if(!core_rst_n) mac_byte_seen<=0; else if(rx_valid) mac_byte_seen<=1;
 // D0 heartbeat; D1 PHY reset+PLL ready; D2 raw PHY RX_CTL observed;
 // D3 valid MOD1/FTR2 protocol accepted (or outgoing reply).
 assign led={udp_seen|tx_seen,raw_rgmii_seen,core_rst_n,heartbeat[25]};
endmodule
