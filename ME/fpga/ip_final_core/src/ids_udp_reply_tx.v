`timescale 1ns/1ps
// Emits complete Ethernet/IPv4/UDP reply bytes. A RGMII DDR serializer is
// connected at the top level. A peer is learned by the RX
// parser; result packets use IDS1 and model completion uses ACK1. UDP checksum
// is deliberately zero (legal for IPv4 UDP), while IPv4 header checksum is set.
module ids_udp_reply_tx #(
 // 192.168.50.50 matches the laptop Ethernet subnet 192.168.50.0/24.
 parameter [31:0] FPGA_IP=32'hC0A83232, parameter [15:0] FPGA_PORT=16'd55003,
 parameter [47:0] FPGA_MAC=48'h025047414901
) (
 input wire clk,input wire rst_n,input wire peer_valid,input wire [47:0] peer_mac,input wire [31:0] peer_ip,input wire [15:0] peer_port,
 input wire reply_toggle,input wire reply_is_ack,
 input wire [31:0] record_sequence,input wire [5:0] class_id,input wire [11:0] leaf_node,input wire [7:0] step_count,input wire [2:0] error_code,input wire [15:0] model_version,
 input wire model_ready,input wire [15:0] accepted_words,input wire [31:0] accepted_records,input wire [31:0] dropped_records,
 output wire [7:0] tx_byte,output wire tx_byte_valid,input wire tx_byte_ready,output reg result_sent,output reg tx_error
);
 localparam [6:0] BODY_BYTES=7'd65;
 reg sending,is_ack,seen_toggle; reg [6:0] index; reg [31:0] seq_l; reg [5:0] class_l; reg [11:0] leaf_l; reg [7:0] steps_l; reg [2:0] error_l; reg [15:0] version_l,words_l; reg ready_l;
 reg [47:0] mac_l; reg [31:0] ip_l; reg [15:0] port_l; reg [31:0] accepted_l,dropped_l; reg [31:0] crc_l;
 wire [7:0] stream_byte; wire stream_ready;
 function [15:0] ip_checksum; input [31:0] dst; reg [31:0] sum; begin
  sum=32'h00004500 + (is_ack ? 16'h002D : 16'h0033) + 16'h0000 + 16'h0000 + 16'h4011 + FPGA_IP[31:16] + FPGA_IP[15:0] + dst[31:16] + dst[15:0];
  sum=(sum[15:0]+sum[31:16]); sum=(sum[15:0]+sum[31:16]); ip_checksum=~sum[15:0];
 end endfunction
 function [7:0] body_byte; input [6:0] i; reg [15:0] csum; begin
  csum=ip_checksum(ip_l);
  if(i<6) body_byte=mac_l[47-i*8 -: 8];
  else if(i<12) body_byte=FPGA_MAC[47-(i-6)*8 -: 8];
  else case(i)
   12:body_byte=8'h08;13:body_byte=8'h00;14:body_byte=8'h45;15:body_byte=0;
   16:body_byte=0;17:body_byte=is_ack?8'h2D:8'h33;18:body_byte=0;19:body_byte=0;20:body_byte=0;21:body_byte=0;22:body_byte=8'h40;23:body_byte=8'h11;
   24:body_byte=csum[15:8];25:body_byte=csum[7:0];26:body_byte=FPGA_IP[31:24];27:body_byte=FPGA_IP[23:16];28:body_byte=FPGA_IP[15:8];29:body_byte=FPGA_IP[7:0];
   30:body_byte=ip_l[31:24];31:body_byte=ip_l[23:16];32:body_byte=ip_l[15:8];33:body_byte=ip_l[7:0];34:body_byte=FPGA_PORT[15:8];35:body_byte=FPGA_PORT[7:0];
   36:body_byte=port_l[15:8];37:body_byte=port_l[7:0];38:body_byte=0;39:body_byte=is_ack?8'h19:8'h1F;40:body_byte=0;41:body_byte=0;
   42:body_byte=is_ack?"A":"I";43:body_byte=is_ack?"C":"D";44:body_byte=is_ack?"K":"S";45:body_byte=8'h31;
   46:body_byte=is_ack?{7'd0,ready_l}:seq_l[7:0];47:body_byte=is_ack?words_l[15:8]:seq_l[15:8];48:body_byte=is_ack?words_l[7:0]:seq_l[23:16];49:body_byte=is_ack?version_l[15:8]:seq_l[31:24];
   50:body_byte=is_ack?version_l[7:0]:{2'd0,class_l};51:body_byte=is_ack?accepted_l[31:24]:leaf_l[11:8];52:body_byte=is_ack?accepted_l[23:16]:leaf_l[7:0];
   53:body_byte=is_ack?accepted_l[15:8]:steps_l;54:body_byte=is_ack?accepted_l[7:0]:{5'd0,error_l};55:body_byte=is_ack?dropped_l[31:24]:version_l[15:8];56:body_byte=is_ack?dropped_l[23:16]:version_l[7:0];
   57:body_byte=is_ack?dropped_l[15:8]:accepted_l[31:24];58:body_byte=is_ack?dropped_l[7:0]:accepted_l[23:16];59:body_byte=is_ack?0:accepted_l[15:8];60:body_byte=is_ack?0:accepted_l[7:0];
   61:body_byte=is_ack?0:dropped_l[31:24];62:body_byte=is_ack?0:dropped_l[23:16];63:body_byte=is_ack?0:dropped_l[15:8];64:body_byte=is_ack?0:dropped_l[7:0];
   default:body_byte=0;
  endcase
 end endfunction
 // Advance CRC one byte per TX cycle.  This avoids a very large combinational
 // 65-byte CRC network and maps efficiently on the GW5A fabric.
 function [31:0] crc_next; input [31:0] crc_in; input [7:0] d; integer b; reg [31:0] c; begin
  c=crc_in;
  for(b=0;b<8;b=b+1) if(c[0]^d[b]) c=(c>>1)^32'hEDB88320; else c=c>>1;
  crc_next=c;
 end endfunction
 // Ethernet transmits the one's-complement of the running reflected CRC.
 // Sending crc_l directly produces a bad FCS that a NIC silently discards.
 wire [31:0] frame_fcs = ~crc_l;
 wire [7:0] frame_byte = (index<7)?8'h55 : (index==7)?8'hD5 : (index<8+BODY_BYTES)?body_byte(index-8) :
                         (index==8+BODY_BYTES)?frame_fcs[7:0] : (index==9+BODY_BYTES)?frame_fcs[15:8] : (index==10+BODY_BYTES)?frame_fcs[23:16] : frame_fcs[31:24];
 assign stream_byte=frame_byte;
 assign tx_byte=stream_byte;
 assign tx_byte_valid=sending;
 assign stream_ready=tx_byte_ready;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin sending<=0;is_ack<=0;seen_toggle<=0;index<=0;seq_l<=0;class_l<=0;leaf_l<=0;steps_l<=0;error_l<=0;version_l<=0;words_l<=0;ready_l<=0;mac_l<=0;ip_l<=0;port_l<=0;accepted_l<=0;dropped_l<=0;crc_l<=0;result_sent<=0;tx_error<=0;end
  else begin
   result_sent<=0;
   if(!sending) begin
    if(peer_valid && (reply_toggle!=seen_toggle)) begin
     seen_toggle<=reply_toggle; is_ack<=reply_is_ack; seq_l<=record_sequence; class_l<=class_id; leaf_l<=leaf_node; steps_l<=step_count; error_l<=error_code; version_l<=model_version; words_l<=accepted_words; ready_l<=model_ready;
     mac_l<=peer_mac; ip_l<=peer_ip; port_l<=peer_port; accepted_l<=accepted_records; dropped_l<=dropped_records; crc_l<=32'hffffffff; index<=0; sending<=1;
    end else if((reply_toggle!=seen_toggle) && !peer_valid) begin seen_toggle<=reply_toggle;tx_error<=1;end
   end else if(stream_ready) begin
    if(index>=8 && index<8+BODY_BYTES) crc_l<=crc_next(crc_l,body_byte(index-8));
    if(index==7+BODY_BYTES+4) begin sending<=0; index<=0; result_sent<=1; end else index<=index+1'b1;
   end
  end
 end
endmodule
