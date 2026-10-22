`timescale 1ns/1ps
// LAN-only ACG525 top: UDP model update + UDP feature input + UDP result output.
module top_acg525_ids_core (
 input wire sys_clk_50,input wire ext_rst_n,
 input wire lan_rmii_ref_clk,input wire [1:0] lan_rxd,input wire lan_crs_dv,
 output wire [1:0] lan_txd,output wire lan_tx_en,output wire [3:0] led
);
 wire [7:0] rx_byte; wire rx_byte_valid,rx_byte_sop,rx_byte_last,rx_frame_error;
 rmii_deserializer #(.STRIP_PREAMBLE(1)) rx(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rxd(lan_rxd),.crs_dv(lan_crs_dv),.rx_byte(rx_byte),.rx_byte_valid(rx_byte_valid),.rx_byte_sop(rx_byte_sop),.rx_byte_last(rx_byte_last),.rx_frame_error(rx_frame_error));
 wire raw_valid,raw_ready,udp_frame_error,udp_seen; wire [28*32-1:0] raw_features; wire [31:0] record_sequence,accepted_records,dropped_records;
 wire model_write_en,model_activate,model_ready,model_ack; wire [11:0] model_write_addr; wire [63:0] model_write_data; wire [15:0] accepted_words;
 wire [47:0] peer_mac; wire [31:0] peer_ip; wire [15:0] peer_port; wire peer_valid;
 wire busy,done,result_valid,active_bank; wire [5:0] class_id; wire [11:0] leaf_node; wire [2:0] error_code; wire [7:0] step_count; wire [15:0] model_version;
 ids_udp_feature_rx udp_rx(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rx_data(rx_byte),.rx_valid(rx_byte_valid),.rx_sop(rx_byte_sop),.engine_busy(busy),.raw_ready(raw_ready),.raw_valid(raw_valid),.raw_features_flat(raw_features),.record_sequence(record_sequence),.accepted_records(accepted_records),.dropped_records(dropped_records),.frame_error(udp_frame_error),.udp_seen(udp_seen),.model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),.model_ready(model_ready),.accepted_words(accepted_words),.model_ack(model_ack),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid));
 ids_top_live classifier(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.raw_record_valid(raw_valid&&model_ready),.raw_record_ready(raw_ready),.raw_features_flat(raw_features),.model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),.busy(busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version));
 reg [31:0] inflight_sequence;
 always @(posedge lan_rmii_ref_clk or negedge ext_rst_n) begin
  if(!ext_rst_n) inflight_sequence<=0;
  else if(raw_valid && raw_ready) inflight_sequence<=record_sequence;
 end
 wire result_sent,tx_error;
 ids_udp_reply_tx udp_tx(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.peer_valid(peer_valid),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.result_valid(result_valid),.record_sequence(inflight_sequence),.class_id(class_id),.leaf_node(leaf_node),.step_count(step_count),.error_code(error_code),.model_version(model_version),.model_ack(model_ack),.model_ready(model_ready),.accepted_words(accepted_words),.accepted_records(accepted_records),.dropped_records(dropped_records),.lan_txd(lan_txd),.lan_tx_en(lan_tx_en),.result_sent(result_sent),.tx_error(tx_error));
 // LED0 heartbeat; LED1 LAN packet accepted; LED2 model ready; LED3 full LAN reply emitted.
 reg [25:0] heartbeat_counter; reg tx_seen;
 reg udp_sync1,udp_sync2,tx_sync1,tx_sync2,model_sync1,model_sync2;
 always @(posedge lan_rmii_ref_clk or negedge ext_rst_n) begin
  if(!ext_rst_n) tx_seen<=0;
  else if(result_sent) tx_seen<=1;
 end
 always @(posedge sys_clk_50 or negedge ext_rst_n) begin
  if(!ext_rst_n) begin heartbeat_counter<=0;udp_sync1<=0;udp_sync2<=0;tx_sync1<=0;tx_sync2<=0;model_sync1<=0;model_sync2<=0;end
  else begin heartbeat_counter<=heartbeat_counter+1'b1;udp_sync1<=udp_seen;udp_sync2<=udp_sync1;tx_sync1<=tx_seen;tx_sync2<=tx_sync1;model_sync1<=model_ready;model_sync2<=model_sync1;end
 end
 assign led={tx_sync2,model_sync2,udp_sync2,heartbeat_counter[25]};
endmodule
