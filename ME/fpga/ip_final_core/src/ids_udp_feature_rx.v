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
 output reg [47:0] peer_mac,output reg [31:0] peer_ip,output reg [15:0] peer_port,output reg peer_valid
);
 reg [8:0] byte_index; reg ip_is_udp,port_ok; reg [7:0] dst_port_hi;
 reg [31:0] sequence_shift; reg [15:0] control_addr_shift; reg [63:0] control_word_shift;
 reg [7:0] protocol_magic; reg [7:0] control_op;
 wire feature_byte=(byte_index>=9'd50)&&(byte_index<=9'd161);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   byte_index<=0; ip_is_udp<=0; port_ok<=0; dst_port_hi<=0; protocol_magic<=0; control_op<=0;
   sequence_shift<=0; control_addr_shift<=0; control_word_shift<=0;
   raw_valid<=0; raw_features_flat<=0; record_sequence<=0; accepted_records<=0; dropped_records<=0; frame_error<=0; udp_seen<=0;
   model_write_en<=0; model_write_addr<=0; model_write_data<=0; model_activate<=0; model_ready<=0; accepted_words<=0; model_ack<=0;
   peer_mac<=0; peer_ip<=0; peer_port<=0; peer_valid<=0;
  end else begin
   frame_error<=0; model_write_en<=0; model_activate<=0; model_ack<=0;
   if(raw_valid && raw_ready) raw_valid<=0;
   if(rx_valid) begin
    if(rx_sop) begin
     byte_index<=1; ip_is_udp<=0; port_ok<=0; protocol_magic<=0; raw_features_flat<=0;
     sequence_shift<=0; control_addr_shift<=0; control_word_shift<=0; peer_valid<=0;
    end else byte_index<=byte_index+1'b1;
    if(byte_index>=9'd6 && byte_index<=9'd11) peer_mac <= {peer_mac[39:0],rx_data};
    if(byte_index>=9'd26 && byte_index<=9'd29) peer_ip <= {peer_ip[23:0],rx_data};
    if(byte_index>=9'd34 && byte_index<=9'd35) peer_port <= {peer_port[7:0],rx_data};
    case(byte_index)
     9'd23: ip_is_udp <= (rx_data==8'd17);
     9'd36: begin dst_port_hi<=rx_data; port_ok<=0; end
     9'd37: port_ok <= ip_is_udp && ({dst_port_hi,rx_data}==UDP_DST_PORT);
     9'd42: protocol_magic <= (rx_data=="F") ? 8'd1 : ((rx_data=="M") ? 8'd2 : 8'd0);
     9'd43: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="T") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="O") ? 8'd2 : 0;
     9'd44: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="R") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="D") ? 8'd2 : 0;
     9'd45: if(protocol_magic==8'd1) protocol_magic <= (rx_data=="2") ? 8'd1 : 0; else if(protocol_magic==8'd2) protocol_magic <= (rx_data=="1") ? 8'd2 : 0;
     9'd46: begin sequence_shift[7:0]<=rx_data; control_op<=rx_data; end
     9'd47: sequence_shift[15:8]<=rx_data;
     9'd48: begin sequence_shift[23:16]<=rx_data; control_addr_shift[7:0]<=rx_data; end
     9'd49: begin sequence_shift[31:24]<=rx_data; control_addr_shift[15:8]<=rx_data; end
     9'd50: control_word_shift[7:0]<=rx_data;
     9'd51: control_word_shift[15:8]<=rx_data;
     9'd52: control_word_shift[23:16]<=rx_data;
     9'd53: control_word_shift[31:24]<=rx_data;
     9'd54: control_word_shift[39:32]<=rx_data;
     9'd55: control_word_shift[47:40]<=rx_data;
     9'd56: control_word_shift[55:48]<=rx_data;
     9'd57: control_word_shift[63:56]<=rx_data;
     default: begin end
    endcase
    if(feature_byte) raw_features_flat <= {rx_data,raw_features_flat[28*32-1:8]};
    if(byte_index==9'd161) begin
     if(ip_is_udp && port_ok && protocol_magic==8'd1) begin
      peer_valid<=1;
      if(!raw_valid || raw_ready) begin raw_valid<=1; record_sequence<=sequence_shift; accepted_records<=accepted_records+1'b1; udp_seen<=1; end
      else begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
     end else if(port_ok) begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
    end
    if(byte_index==9'd46 && ip_is_udp && port_ok && protocol_magic==8'd2 && rx_data==8'd1) begin
      model_ready<=0; accepted_words<=0; peer_valid<=1; udp_seen<=1;
    end
    if(byte_index==9'd57 && ip_is_udp && port_ok && protocol_magic==8'd2 && control_op==8'd2) begin
      peer_valid<=1;
      if(!engine_busy && control_addr_shift < NODE_COUNT) begin
       model_write_en<=1; model_write_addr<=control_addr_shift[11:0]; model_write_data<={rx_data,control_word_shift[55:0]}; accepted_words<=accepted_words+1'b1; udp_seen<=1;
      end else begin dropped_records<=dropped_records+1'b1; frame_error<=1; end
    end
    if(byte_index==9'd46 && ip_is_udp && port_ok && protocol_magic==8'd2 && rx_data==8'd3) begin
      peer_valid<=1; udp_seen<=1;
      if(!engine_busy && accepted_words==NODE_COUNT) begin model_activate<=1; model_ready<=1; model_ack<=1; end
      else begin model_ack<=1; frame_error<=1; end
    end
   end
  end
 end
endmodule
