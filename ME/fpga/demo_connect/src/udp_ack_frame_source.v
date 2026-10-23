`timescale 1ns/1ps
// Complete ACK Ethernet frame source for the onboard RGMII serializer.
module udp_ack_frame_source #(
 parameter [31:0] FPGA_IP=32'hC0A83232,
 parameter [47:0] FPGA_MAC=48'h025047414901,
 parameter [15:0] FPGA_PORT=16'd55003
)(
 input wire clk,input wire rst_n,input wire request,input wire [31:0] seq_in,
 input wire [47:0] peer_mac,input wire [31:0] peer_ip,input wire [15:0] peer_port,
 input wire read_en,output reg [7:0] data,output reg last,output reg valid,
 output wire empty,output wire packet_available,output reg frame_sent
);
 localparam [6:0] LAST_INDEX=7'd71;
 reg active;reg [6:0] index;reg [31:0] seq_l,ip_l,crc_l;reg [47:0] mac_l;reg [15:0] port_l;
 function [15:0] ip_checksum;input [31:0] dst;reg [31:0] sum;begin
  sum=16'h4500+16'h0024+16'h0000+16'h0000+16'h4011+FPGA_IP[31:16]+FPGA_IP[15:0]+dst[31:16]+dst[15:0];
  sum=sum[15:0]+sum[31:16];sum=sum[15:0]+sum[31:16];ip_checksum=~sum[15:0];
 end endfunction
 function [7:0] body_byte;input [6:0] i;reg [15:0] csum;begin
  csum=ip_checksum(ip_l);
  if(i<6) body_byte=mac_l[47-i*8 -:8];
  else if(i<12) body_byte=FPGA_MAC[47-(i-6)*8 -:8];
  else case(i)
   12:body_byte=8'h08;13:body_byte=0;14:body_byte=8'h45;15:body_byte=0;16:body_byte=0;17:body_byte=8'h24;18:body_byte=0;19:body_byte=0;20:body_byte=0;21:body_byte=0;22:body_byte=8'h40;23:body_byte=8'h11;
   24:body_byte=csum[15:8];25:body_byte=csum[7:0];26:body_byte=FPGA_IP[31:24];27:body_byte=FPGA_IP[23:16];28:body_byte=FPGA_IP[15:8];29:body_byte=FPGA_IP[7:0];
   30:body_byte=ip_l[31:24];31:body_byte=ip_l[23:16];32:body_byte=ip_l[15:8];33:body_byte=ip_l[7:0];34:body_byte=FPGA_PORT[15:8];35:body_byte=FPGA_PORT[7:0];36:body_byte=port_l[15:8];37:body_byte=port_l[7:0];38:body_byte=0;39:body_byte=16;40:body_byte=0;41:body_byte=0;
   42:body_byte="A";43:body_byte="C";44:body_byte="K";45:body_byte="1";46:body_byte=seq_l[7:0];47:body_byte=seq_l[15:8];48:body_byte=seq_l[23:16];49:body_byte=seq_l[31:24];
   default:body_byte=0;
  endcase
 end endfunction
 function [31:0] crc_next;input [31:0] crc_in;input [7:0] d;integer b;reg [31:0] c;begin
  c=crc_in;for(b=0;b<8;b=b+1) if(c[0]^d[b]) c=(c>>1)^32'hedb88320;else c=c>>1;crc_next=c;
 end endfunction
 wire [31:0] fcs=~crc_l;
 wire [7:0] selected_byte=(index<7)?8'h55:(index==7)?8'hd5:(index<68)?body_byte(index-8):(index==68)?fcs[7:0]:(index==69)?fcs[15:8]:(index==70)?fcs[23:16]:fcs[31:24];
 assign empty=!active;assign packet_available=active;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin active<=0;index<=0;seq_l<=0;ip_l<=0;mac_l<=0;port_l<=0;crc_l<=32'hffffffff;data<=0;last<=0;valid<=0;frame_sent<=0;end
  else begin
   valid<=0;frame_sent<=0;
   if(!active) begin
    if(request) begin active<=1;index<=0;seq_l<=seq_in;ip_l<=peer_ip;mac_l<=peer_mac;port_l<=peer_port;crc_l<=32'hffffffff;end
   end else if(read_en) begin
    data<=selected_byte;last<=(index==LAST_INDEX);valid<=1;
    if(index>=8&&index<68) crc_l<=crc_next(crc_l,body_byte(index-8));
    if(index==LAST_INDEX) begin active<=0;index<=0;frame_sent<=1;end else index<=index+1'b1;
   end
  end
 end
endmodule
