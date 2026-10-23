`timescale 1ns/1ps
// Complete ingress regression: real DDR nibbles, preamble/SFD, Ethernet,
// IPv4, UDP, MOD1 de-duplication/commit and FTR2 feature extraction.
module tb_rgmii_udp_end_to_end;
 localparam NODE_COUNT=4;
 reg clk=0,rst_n=0,rx_ctl=0;reg [3:0] rxd=0;reg engine_busy=0,raw_ready=1;
 wire [7:0] rx_byte;wire rx_valid,rx_sop,rx_last,rx_phy_error;
 wire raw_valid,frame_error,udp_seen,write_en,activate,model_ready,model_ack,peer_valid;
 wire [28*32-1:0] features;wire [31:0] record_seq,accepted,dropped,peer_ip;
 wire [11:0] write_addr;wire [63:0] write_data;wire [15:0] words,peer_port;wire [47:0] peer_mac;
 wire [31:0] frames,ipv4,ip_udp,dst_port,magic,h0,h1,h2;
 integer writes=0;reg [63:0] observed_words[0:NODE_COUNT-1];integer k;
 always #10 clk=~clk;

 rgmii_rx_byte phy_rx(.rx_clk(clk),.rst_n(rst_n),.sample_ce(1'b1),.rxd(rxd),.rx_ctl(rx_ctl),
  .byte_data(rx_byte),.byte_valid(rx_valid),.byte_sop(rx_sop),.byte_last(rx_last),.frame_error(rx_phy_error));
 ids_udp_feature_rx #(.NODE_COUNT(NODE_COUNT)) parser(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_byte),.rx_valid(rx_valid),.rx_sop(rx_sop),.engine_busy(engine_busy),.raw_ready(raw_ready),
  .raw_valid(raw_valid),.raw_features_flat(features),.record_sequence(record_seq),.accepted_records(accepted),.dropped_records(dropped),.frame_error(frame_error),.udp_seen(udp_seen),
  .model_write_en(write_en),.model_write_addr(write_addr),.model_write_data(write_data),.model_activate(activate),.model_ready(model_ready),.accepted_words(words),.model_ack(model_ack),
  .peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid),.trace_frames(frames),.trace_ipv4(ipv4),.trace_ip_udp(ip_udp),.trace_dst_port(dst_port),.trace_magic(magic),.trace_hdr0(h0),.trace_hdr1(h1),.trace_hdr2(h2));
 always @(posedge clk) if(write_en) begin writes=writes+1;observed_words[write_addr]=write_data;end

 task ddr_byte;input [7:0] b;begin
  @(negedge clk);#1 rxd=b[3:0];rx_ctl=1;@(posedge clk);
  @(negedge clk);#1 rxd=b[7:4];rx_ctl=1;@(posedge clk);
 end endtask
 task finish_frame;begin
  @(negedge clk);#1 rx_ctl=0;rxd=0;repeat(8)@(posedge clk);
 end endtask
 task prefix;begin repeat(7)ddr_byte(8'h55);ddr_byte(8'hD5);end endtask
 task common_byte;input integer i;input [15:0] ether_type;input [15:0] udp_dst;output [7:0] x;begin
  x=0;
  if(i<=5)x=8'hFF;
  else case(i)
   6:x=8'hC4;7:x=8'hC6;8:x=8'hE6;9:x=8'h18;10:x=8'h5D;11:x=8'h9E;
   12:x=ether_type[15:8];13:x=ether_type[7:0];14:x=8'h45;23:x=8'd17;
   26:x=8'd192;27:x=8'd168;28:x=8'd50;29:x=8'd22;
   30:x=8'd192;31:x=8'd168;32:x=8'd50;33:x=8'd50;
   34:x=8'hD6;35:x=8'hDB;36:x=udp_dst[15:8];37:x=udp_dst[7:0];
   default:x=0;
  endcase
 end endtask
 task mod_frame;input [7:0] op;input [15:0] addr;input [63:0] word;input [15:0] ether_type;input [15:0] udp_dst;integer i;reg [7:0] x;begin
  prefix();
  for(i=0;i<=56;i=i+1)begin
   common_byte(i,ether_type,udp_dst,x);
   case(i)
    42:x="M";43:x="O";44:x="D";45:x="1";46:x=op;
    47:x=addr[7:0];48:x=addr[15:8];
    49:x=word[7:0];50:x=word[15:8];51:x=word[23:16];52:x=word[31:24];
    53:x=word[39:32];54:x=word[47:40];55:x=word[55:48];56:x=word[63:56];
   endcase
   ddr_byte(x);
  end
  finish_frame();
 end endtask
 task ftr_frame;input [31:0] seq;integer i,j;reg [7:0] x;begin
  prefix();
  for(i=0;i<=161;i=i+1)begin
   common_byte(i,16'h0800,16'd55002,x);
   case(i)42:x="F";43:x="T";44:x="R";45:x="2";46:x=seq[7:0];47:x=seq[15:8];48:x=seq[23:16];49:x=seq[31:24];endcase
   if(i>=50)begin j=i-50;x=j[7:0];end
   ddr_byte(x);
  end
  finish_frame();
 end endtask

 initial begin
  for(k=0;k<NODE_COUNT;k=k+1)observed_words[k]=0;
  repeat(4)@(posedge clk);rst_n=1;
  // Non-IPv4 and wrong-port frames must never write model memory.
  mod_frame(8'd2,16'd0,64'h1111,16'h0806,16'd55002);
  mod_frame(8'd2,16'd0,64'h2222,16'h0800,16'd55001);
  if(words!==0||writes!==0)$fatal(1,"filtering failed words=%0d writes=%0d",words,writes);
  mod_frame(8'd1,0,0,16'h0800,16'd55002);
  mod_frame(8'd2,0,64'h0123456789ABCDEF,16'h0800,16'd55002);
  mod_frame(8'd2,1,64'h1111222233334444,16'h0800,16'd55002);
  mod_frame(8'd2,2,64'hAAAABBBBCCCCDDDD,16'h0800,16'd55002);
  mod_frame(8'd2,2,64'hAAAABBBBCCCCDDDD,16'h0800,16'd55002); // duplicate
  mod_frame(8'd2,3,64'hFEDCBA9876543210,16'h0800,16'd55002);
  if(words!==NODE_COUNT||writes!==5)$fatal(1,"model writes/de-dup failed words=%0d writes=%0d",words,writes);
  if(observed_words[0]!==64'h0123456789ABCDEF||observed_words[3]!==64'hFEDCBA9876543210)$fatal(1,"model word corruption");
  mod_frame(8'd3,0,0,16'h0800,16'd55002);
  if(!model_ready||!peer_valid)$fatal(1,"commit/peer failed ready=%b peer=%b",model_ready,peer_valid);
  ftr_frame(32'h12345678);
  repeat(4)@(posedge clk);
  if(accepted!==1||record_seq!==32'h12345678||features[31:0]!==32'h03020100||features[895:864]!==32'h6F6E6D6C)$fatal(1,"FTR2 failed acc=%0d seq=%h f0=%h f27=%h",accepted,record_seq,features[31:0],features[895:864]);
  if(h0!==32'hC4C6E618||h1!==32'h5D9E0800||h2!==32'h00004500)$fatal(1,"header alignment failed %h %h %h",h0,h1,h2);
  $display("RGMII_UDP_E2E_PASS frames=%0d ipv4=%0d udp=%0d port=%0d magic=%0d words=%0d",frames,ipv4,ip_udp,dst_port,magic,words);
  $finish;
 end
endmodule
