`timescale 1ns/1ps
// Packet-level regression for ACK1 and IDS1, including Ethernet FCS.
module tb_udp_reply_tx;
 reg clk=0,rst_n=0,peer_valid=1,reply_toggle=0,reply_is_ack=0;
 reg [47:0] peer_mac=48'hC4C6E6185D9E;
 reg [31:0] peer_ip=32'hC0A83216,seq=32'h12345678,accepted=32'd7,dropped=32'd2;
 reg [15:0] peer_port=16'd55003,version=16'h0102,words=16'd1273;
 reg [5:0] cls=6'h15;reg [11:0] leaf=12'hABC;reg [7:0] steps=8'h23;reg [2:0] err=3'h3;reg model_ready=1;
 wire [7:0] tx_byte;wire tx_valid,result_sent,tx_error;reg tx_ready=1;
 reg [7:0] captured[0:255];integer count=0;integer i;reg [31:0] crc,expected_fcs,observed_fcs;
 always #5 clk=~clk;
 ids_udp_reply_tx dut(.clk(clk),.rst_n(rst_n),.peer_valid(peer_valid),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),
  .reply_toggle(reply_toggle),.reply_is_ack(reply_is_ack),.record_sequence(seq),.class_id(cls),.leaf_node(leaf),.step_count(steps),.error_code(err),
  .model_version(version),.model_ready(model_ready),.accepted_words(words),.accepted_records(accepted),.dropped_records(dropped),
  .tx_byte(tx_byte),.tx_byte_valid(tx_valid),.tx_byte_ready(tx_ready),.result_sent(result_sent),.tx_error(tx_error));
 always @(posedge clk) if(tx_valid&&tx_ready) begin captured[count]=tx_byte;count=count+1;end
 function [31:0] crc_next;input [31:0] c_in;input [7:0] d;integer b;reg [31:0] c;begin
  c=c_in;for(b=0;b<8;b=b+1)if(c[0]^d[b])c=(c>>1)^32'hEDB88320;else c=c>>1;crc_next=c;
 end endfunction
 task check_common;begin
  if(count!=77)$fatal(1,"reply byte count=%0d expected=77",count);
  for(i=0;i<7;i=i+1)if(captured[i]!==8'h55)$fatal(1,"bad preamble byte %0d",i);
  if(captured[7]!==8'hD5)$fatal(1,"bad SFD");
  if({captured[8],captured[9],captured[10],captured[11],captured[12],captured[13]}!==peer_mac)$fatal(1,"bad destination MAC");
  if({captured[20],captured[21]}!==16'h0800)$fatal(1,"bad EtherType");
  if({captured[38],captured[39],captured[40],captured[41]}!==peer_ip)$fatal(1,"bad destination IP");
  if({captured[44],captured[45]}!==peer_port)$fatal(1,"bad destination UDP port");
  crc=32'hFFFFFFFF;for(i=8;i<73;i=i+1)crc=crc_next(crc,captured[i]);expected_fcs=~crc;
  observed_fcs={captured[76],captured[75],captured[74],captured[73]};
  if(observed_fcs!==expected_fcs)$fatal(1,"bad FCS got=%08x expected=%08x",observed_fcs,expected_fcs);
 end endtask
 task launch_and_wait;begin
  count=0;reply_toggle=~reply_toggle;
  wait(result_sent);@(posedge clk);#1;
 end endtask
 initial begin
  repeat(3)@(posedge clk);rst_n=1;
  reply_is_ack=1;launch_and_wait();check_common();
  if({captured[50],captured[51],captured[52],captured[53]}!==32'h41434B31)$fatal(1,"ACK1 magic absent");
  if(captured[54]!==1 || {captured[55],captured[56]}!==16'd1273 || {captured[57],captured[58]}!==version)$fatal(1,"ACK1 payload incorrect");
  reply_is_ack=0;launch_and_wait();check_common();
  if({captured[50],captured[51],captured[52],captured[53]}!==32'h49445331)$fatal(1,"IDS1 magic absent");
  if({captured[57],captured[56],captured[55],captured[54]}!==seq || captured[58]!=={2'd0,cls} || {captured[59][3:0],captured[60]}!==leaf)$fatal(1,"IDS1 payload incorrect");
  if(tx_error)$fatal(1,"unexpected TX error");
  $display("UDP_REPLY_TX_PASS ack_ids_bytes=%0d fcs=%08x",count,observed_fcs);$finish;
 end
endmodule
