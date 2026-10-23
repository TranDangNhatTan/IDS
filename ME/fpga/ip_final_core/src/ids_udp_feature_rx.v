`timescale 1ns/1ps
// LAN ingress protocol (IPv4 IHL=20, UDP destination port 55002):
// FTR2 + seq_le32 + 28 x uint32_le -> classifier record
// MOD1 + op + payload              -> model loader
// Sender MAC/IP/UDP source port are learned for UDP replies.
module ids_udp_feature_rx #(parameter UDP_DST_PORT=16'd55002, parameter NODE_COUNT=1273) (
 input wire clk,input wire rst_n,input wire [7:0] rx_data,input wire rx_valid,input wire rx_sop,
 input wire engine_busy,input wire raw_ready,
 output reg raw_valid,output reg [28*32-1:0] raw_features_flat,output reg [31:0] record_sequence,
 output reg [31:0] accepted_records,output reg [31:0] dropped_records,output reg frame_error,output reg udp_seen,
 output reg model_write_en,output reg [11:0] model_write_addr,output reg [63:0] model_write_data,
 output reg model_activate,output reg model_ready,output reg [15:0] accepted_words,output reg model_ack,
 output reg [47:0] peer_mac,output reg [31:0] peer_ip,output reg [15:0] peer_port,output reg peer_valid,
 // Passive counters exported in DBG1 telemetry. They identify exactly the
 // first Ethernet/IP/UDP parsing stage at which real board traffic stops.
 output reg [31:0] trace_frames,output reg [31:0] trace_ipv4,
 output reg [31:0] trace_ip_udp,output reg [31:0] trace_dst_port,output reg [31:0] trace_magic,
 output reg [31:0] trace_hdr0,output reg [31:0] trace_hdr1,output reg [31:0] trace_hdr2
);
 // `byte_index` holds the index for the *next* received byte.  Do not use it
 // directly for decoding: on rx_sop its old value belongs to the preceding
 // Ethernet frame.  `current_byte_index` makes every frame start at byte 0.
 reg [8:0] byte_index; reg eth_is_ipv4,ip_is_udp,port_ok; reg [7:0] ethertype_hi,dst_port_hi;
 reg [31:0] sequence_shift; reg [15:0] control_addr_shift; reg [63:0] control_word_shift;
 reg [7:0] protocol_magic; reg [7:0] control_op;
 // A model word is addressed, so it is safe to retransmit it.  This bitmap
 // makes the BRAM commit transactional: accepted_words counts *unique*
 // addresses, never duplicate UDP deliveries.
 reg [NODE_COUNT-1:0] model_word_seen;
 // Completion is retained in the RX clock domain.  UART and reply logic may
 // observe the multi-bit count asynchronously, but model activation must
 // never depend on a torn cross-clock count value.
 reg model_image_complete;
 wire [8:0] current_byte_index = rx_sop ? 9'd0 : byte_index;
 wire feature_byte=(current_byte_index>=9'd50)&&(current_byte_index<=9'd161);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   byte_index<=0; eth_is_ipv4<=0;ip_is_udp<=0;port_ok<=0;ethertype_hi<=0;dst_port_hi<=0;protocol_magic<=0;control_op<=0;
   model_word_seen<={NODE_COUNT{1'b0}};model_image_complete<=0;
   sequence_shift<=0; control_addr_shift<=0; control_word_shift<=0;
   raw_valid<=0; raw_features_flat<=0; record_sequence<=0; accepted_records<=0; dropped_records<=0; frame_error<=0; udp_seen<=0;
   model_write_en<=0; model_write_addr<=0; model_write_data<=0; model_activate<=0; model_ready<=0; accepted_words<=0; model_ack<=0;
   peer_mac<=0; peer_ip<=0; peer_port<=0; peer_valid<=0;
   trace_frames<=0;trace_ipv4<=0;trace_ip_udp<=0;trace_dst_port<=0;trace_magic<=0;
   trace_hdr0<=0;trace_hdr1<=0;trace_hdr2<=0;
  end else begin
   frame_error<=0; model_write_en<=0; model_activate<=0; model_ack<=0;
   if(raw_valid && raw_ready) raw_valid<=0;
   if(rx_valid) begin
    if(rx_sop) begin
     byte_index<=1;eth_is_ipv4<=0;ip_is_udp<=0;port_ok<=0;protocol_magic<=0;raw_features_flat<=0;
     // Keep the last valid peer until another accepted UDP packet replaces
     // it. Clearing it at every SOP could erase the reply destination while
     // the classifier was still processing the preceding packet.
     sequence_shift<=0; control_addr_shift<=0; control_word_shift<=0;
     trace_hdr0<=0;trace_hdr1<=0;trace_hdr2<=0;
     trace_frames<=trace_frames+1'b1;
    end else byte_index<=byte_index+1'b1;
    if(current_byte_index>=9'd6 && current_byte_index<=9'd11) peer_mac <= {peer_mac[39:0],rx_data};
    // Preserve header bytes 6..15 for hardware trace: source MAC, EtherType
    // and IPv4 version. This makes an RGMII byte/nibble ordering error visible.
    if(current_byte_index>=9'd6 && current_byte_index<=9'd9) trace_hdr0<={trace_hdr0[23:0],rx_data};
    if(current_byte_index>=9'd10 && current_byte_index<=9'd13) trace_hdr1<={trace_hdr1[23:0],rx_data};
    if(current_byte_index>=9'd14 && current_byte_index<=9'd15) trace_hdr2<={trace_hdr2[23:0],rx_data};
    if(current_byte_index>=9'd26 && current_byte_index<=9'd29) peer_ip <= {peer_ip[23:0],rx_data};
    if(current_byte_index>=9'd34 && current_byte_index<=9'd35) peer_port <= {peer_port[7:0],rx_data};
    case(current_byte_index)
     9'd12: ethertype_hi<=rx_data;
     9'd13: begin eth_is_ipv4<=({ethertype_hi,rx_data}==16'h0800);if({ethertype_hi,rx_data}==16'h0800) trace_ipv4<=trace_ipv4+1'b1;end
     9'd23: begin ip_is_udp <= eth_is_ipv4&&(rx_data==8'd17); if(eth_is_ipv4&&(rx_data==8'd17)) trace_ip_udp<=trace_ip_udp+1'b1; end
     9'd36: begin dst_port_hi<=rx_data; port_ok<=0; end
     9'd37: begin
      port_ok <= ip_is_udp && ({dst_port_hi,rx_data}==UDP_DST_PORT);
      if(ip_is_udp && ({dst_port_hi,rx_data}==UDP_DST_PORT)) trace_dst_port<=trace_dst_port+1'b1;
     end
     9'd42: protocol_magic <= (rx_data=="F") ? 8'd1 : ((rx_data=="M") ? 8'd2 : 8'd0);
     9'd43: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="T") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="O") ? 8'd2 : 0;
     9'd44: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="R") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="D") ? 8'd2 : 0;
     9'd45: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="2") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="1") ? 8'd2 : 0;
     // FTR2 layout: sequence at 46..49, features at 50..161.
     // MOD1 layout: op at 46, address at 47..48, word at 49..56.
     9'd46: begin sequence_shift[7:0]<=rx_data; control_op<=rx_data; end
     9'd47: begin sequence_shift[15:8]<=rx_data; control_addr_shift[7:0]<=rx_data; end
     9'd48: begin sequence_shift[23:16]<=rx_data; control_addr_shift[15:8]<=rx_data; end
     9'd49: begin sequence_shift[31:24]<=rx_data; control_word_shift[7:0]<=rx_data; end
     9'd50: control_word_shift[15:8]<=rx_data;
     9'd51: control_word_shift[23:16]<=rx_data;
     9'd52: control_word_shift[31:24]<=rx_data;
     9'd53: control_word_shift[39:32]<=rx_data;
     9'd54: control_word_shift[47:40]<=rx_data;
     9'd55: control_word_shift[55:48]<=rx_data;
     9'd56: control_word_shift[63:56]<=rx_data;
     default: begin end
    endcase
    if(current_byte_index==9'd45 && ((protocol_magic==8'd1 && rx_data=="2") || (protocol_magic==8'd2 && rx_data=="1"))) trace_magic<=trace_magic+1'b1;
    if(feature_byte) raw_features_flat <= {rx_data,raw_features_flat[28*32-1:8]};
    if(current_byte_index==9'd161) begin
     if(ip_is_udp && port_ok && protocol_magic==8'd1) begin
      peer_valid<=1;
      if(!raw_valid || raw_ready) begin raw_valid<=1; record_sequence<=sequence_shift; accepted_records<=accepted_records+1'b1; udp_seen<=1; end
      else begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
     end else if(port_ok) begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
    end
    if(current_byte_index==9'd46 && ip_is_udp && port_ok && protocol_magic==8'd2 && rx_data==8'd1) begin
      model_ready<=0; accepted_words<=0; model_word_seen<={NODE_COUNT{1'b0}}; model_image_complete<=0; peer_valid<=1; udp_seen<=1;
    end
    if(current_byte_index==9'd56 && ip_is_udp && port_ok && protocol_magic==8'd2 && control_op==8'd2) begin
      peer_valid<=1;
      if(!engine_busy && control_addr_shift < NODE_COUNT) begin
       // Always refresh the addressed BRAM word; increment only on its first
       // valid delivery in this transfer.
       model_write_en<=1; model_write_addr<=control_addr_shift[11:0]; model_write_data<={rx_data,control_word_shift[55:0]};
       if(!model_word_seen[control_addr_shift]) begin
        model_word_seen[control_addr_shift]<=1'b1;
        if(accepted_words < NODE_COUNT) accepted_words<=accepted_words+1'b1;
        if(accepted_words == NODE_COUNT-1) model_image_complete<=1'b1;
       end
       udp_seen<=1;
      end else begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
    end
    if(current_byte_index==9'd46 && ip_is_udp && port_ok && protocol_magic==8'd2 && rx_data==8'd3) begin
      peer_valid<=1; udp_seen<=1;
      // COMMIT is idempotent.  The server may repeat it when an ACK is lost;
      // toggling the active bank twice would otherwise restore the old model.
      if(model_ready) model_ack<=1;
      else if(!engine_busy && model_image_complete) begin model_activate<=1; model_ready<=1; model_ack<=1; end
      else begin model_ack<=1; frame_error<=1; end
    end
   end
  end
 end
endmodule
