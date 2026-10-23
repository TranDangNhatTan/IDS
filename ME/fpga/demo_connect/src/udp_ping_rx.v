`timescale 1ns/1ps
// Parses a fixed Ethernet/IPv4/IHL=20/UDP frame carrying PING + uint32_le.
module udp_ping_rx #(parameter [15:0] UDP_DST_PORT=16'd55002)(
 input wire clk,input wire rst_n,input wire [7:0] byte_data,input wire byte_valid,input wire byte_sop,
 output reg ping_valid,output reg [31:0] ping_sequence,
 output reg [47:0] peer_mac,output reg [31:0] peer_ip,output reg [15:0] peer_port,output reg peer_valid,output reg rx_seen
);
 reg [8:0] index;reg ip_udp,port_ok;reg [7:0] port_hi,magic;reg [31:0] seq;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin index<=0;ip_udp<=0;port_ok<=0;port_hi<=0;magic<=0;seq<=0;ping_valid<=0;ping_sequence<=0;peer_mac<=0;peer_ip<=0;peer_port<=0;peer_valid<=0;rx_seen<=0;end
  else begin
   ping_valid<=0;
   if(byte_valid) begin
    if(byte_sop) begin index<=1;ip_udp<=0;port_ok<=0;magic<=0;seq<=0;peer_valid<=0;end else index<=index+1'b1;
    if(index>=6 && index<=11) peer_mac<={peer_mac[39:0],byte_data};
    if(index>=26 && index<=29) peer_ip<={peer_ip[23:0],byte_data};
    if(index>=34 && index<=35) peer_port<={peer_port[7:0],byte_data};
    case(index)
     23:ip_udp<=(byte_data==8'd17);
     36:port_hi<=byte_data;
     37:port_ok<=ip_udp && ({port_hi,byte_data}==UDP_DST_PORT);
     42:magic<=(byte_data=="P")?1:0;
     43:magic<=(magic==1 && byte_data=="I")?2:0;
     44:magic<=(magic==2 && byte_data=="N")?3:0;
     45:magic<=(magic==3 && byte_data=="G")?4:0;
     46:seq[7:0]<=byte_data;
     47:seq[15:8]<=byte_data;
     48:seq[23:16]<=byte_data;
     49:begin
      seq[31:24]<=byte_data;
      if(ip_udp && port_ok && magic==4) begin
       ping_sequence<={byte_data,seq[23:0]}; ping_valid<=1;peer_valid<=1;rx_seen<=1;
      end
     end
     default:begin end
    endcase
   end
  end
 end
endmodule
