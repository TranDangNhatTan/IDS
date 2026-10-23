`timescale 1ns/1ps
// Periodic broadcast UDP trace for board bring-up.  It needs no ARP and is
// deliberately independent of MOD1/FTR2 acceptance, so the dashboard can
// reveal the exact receive-parser stage reached by real Ethernet traffic.
// Payload: DBG1 + parser counters + the first received header words and the
// raw RX_CTL cycle count.  This makes a physical RX-pin failure distinguishable
// from a byte-alignment or IPv4/UDP parser failure.
module ids_lan_trace_tx(
 input wire clk,input wire rst_n,input wire [31:0] frames,input wire [31:0] ipv4,
 input wire [31:0] ip_udp,input wire [31:0] dst_port,input wire [31:0] magic,
 input wire [31:0] hdr0,input wire [31:0] hdr1,input wire [31:0] hdr2,input wire [31:0] raw_cycles,
 output wire [7:0] tx_byte,output wire tx_valid,input wire tx_ready,output reg busy
);
 localparam integer PERIOD=12_500_000; // 0.5 s at 25 MHz
 localparam [6:0] BODY_BYTES=7'd82;
 reg [23:0] timer; reg [6:0] index; reg [31:0] crc;
 reg [31:0] f_l,i_l,u_l,p_l,m_l,h0_l,h1_l,h2_l,r_l;
 function [15:0] ip_sum; input dummy; reg [31:0] s; begin
  // IPv4: src 192.168.50.50, dst 192.168.50.255, total length 68.
  s=16'h4500+16'h0044+16'h0000+16'h0000+16'h4011+16'hC0A8+16'h3232+16'hC0A8+16'h32FF;
  s=s[15:0]+s[31:16];s=s[15:0]+s[31:16];ip_sum=~s[15:0];
 end endfunction
 function [7:0] body; input [6:0] n; reg [15:0] c; begin
  c=ip_sum(1'b0);
  if(n<6) body=8'hFF;
  else if(n==6) body=8'h02; else if(n==7) body=8'h50; else if(n==8) body=8'h47;
  else if(n==9) body=8'h41; else if(n==10) body=8'h49; else if(n==11) body=8'h01;
  else case(n)
   12:body=8'h08;13:body=8'h00;14:body=8'h45;15:body=0;16:body=0;17:body=8'h34;
   18:body=0;19:body=0;20:body=0;21:body=0;22:body=8'h40;23:body=8'h11;
   24:body=c[15:8];25:body=c[7:0];26:body=8'hC0;27:body=8'hA8;28:body=8'h32;29:body=8'h32;
   30:body=8'hC0;31:body=8'hA8;32:body=8'h32;33:body=8'hFF;
   // UDP source/destination = dashboard listener 55003 = 16'hD6DB.
   34:body=8'hD6;35:body=8'hDB;36:body=8'hD6;37:body=8'hDB;38:body=0;39:body=8'h30;40:body=0;41:body=0;
   42:body="D";43:body="B";44:body="G";45:body="1";
   46:body=f_l[31:24];47:body=f_l[23:16];48:body=f_l[15:8];49:body=f_l[7:0];
   50:body=i_l[31:24];51:body=i_l[23:16];52:body=i_l[15:8];53:body=i_l[7:0];
   54:body=u_l[31:24];55:body=u_l[23:16];56:body=u_l[15:8];57:body=u_l[7:0];
   58:body=p_l[31:24];59:body=p_l[23:16];60:body=p_l[15:8];61:body=p_l[7:0];
   62:body=m_l[31:24];63:body=m_l[23:16];64:body=m_l[15:8];65:body=m_l[7:0];
   66:body=h0_l[31:24];67:body=h0_l[23:16];68:body=h0_l[15:8];69:body=h0_l[7:0];
   70:body=h1_l[31:24];71:body=h1_l[23:16];72:body=h1_l[15:8];73:body=h1_l[7:0];
   74:body=h2_l[31:24];75:body=h2_l[23:16];76:body=h2_l[15:8];77:body=h2_l[7:0];
   78:body=r_l[31:24];79:body=r_l[23:16];80:body=r_l[15:8];81:body=r_l[7:0];
   default:body=0;
  endcase
 end endfunction
 function [31:0] crc_next; input [31:0] c0; input [7:0] d; integer b; reg [31:0] c; begin
  c=c0; for(b=0;b<8;b=b+1) if(c[0]^d[b]) c=(c>>1)^32'hEDB88320; else c=c>>1; crc_next=c;
 end endfunction
 wire [31:0] frame_fcs=~crc;
 wire [7:0] out_byte=(index<7)?8'h55:(index==7)?8'hD5:(index<8+BODY_BYTES)?body(index-8):
   (index==8+BODY_BYTES)?frame_fcs[7:0]:(index==9+BODY_BYTES)?frame_fcs[15:8]:(index==10+BODY_BYTES)?frame_fcs[23:16]:frame_fcs[31:24];
 assign tx_byte=out_byte; assign tx_valid=busy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin timer<=0;index<=0;crc<=0;busy<=0;f_l<=0;i_l<=0;u_l<=0;p_l<=0;m_l<=0;h0_l<=0;h1_l<=0;h2_l<=0;r_l<=0;end
  else if(!busy) begin
   if(timer==PERIOD-1) begin timer<=0;busy<=1;index<=0;crc<=32'hFFFFFFFF;f_l<=frames;i_l<=ipv4;u_l<=ip_udp;p_l<=dst_port;m_l<=magic;h0_l<=hdr0;h1_l<=hdr1;h2_l<=hdr2;r_l<=raw_cycles;end
   else timer<=timer+1'b1;
  end else if(tx_ready) begin
   if(index>=8 && index<8+BODY_BYTES) crc<=crc_next(crc,body(index-8));
   if(index==7+BODY_BYTES+4) begin busy<=0;index<=0;end else index<=index+1'b1;
  end
 end
endmodule
