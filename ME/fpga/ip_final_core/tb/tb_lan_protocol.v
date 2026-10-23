`timescale 1ns/1ps
module tb_lan_protocol;
 reg clk=0,rst_n=0,valid=0,sop=0,engine_busy=0,raw_ready=1; reg [7:0] data=0;
 wire raw_valid,frame_error,write_en,activate,ready,ack,peer_valid,udp_seen; wire [28*32-1:0] features; wire [31:0] seq,accepted,dropped,peer_ip; wire [11:0] waddr; wire [63:0] wdata; wire [15:0] words,peer_port; wire [47:0] peer_mac;
 ids_udp_feature_rx dut(.clk(clk),.rst_n(rst_n),.rx_data(data),.rx_valid(valid),.rx_sop(sop),.engine_busy(engine_busy),.raw_ready(raw_ready),.raw_valid(raw_valid),.raw_features_flat(features),.record_sequence(seq),.accepted_records(accepted),.dropped_records(dropped),.frame_error(frame_error),.udp_seen(udp_seen),.model_write_en(write_en),.model_write_addr(waddr),.model_write_data(wdata),.model_activate(activate),.model_ready(ready),.accepted_words(words),.model_ack(ack),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid));
 always #10 clk=~clk;
 task put; input [7:0] x; input first; begin @(negedge clk);data=x;valid=1;sop=first;@(negedge clk);valid=0;sop=0;end endtask
 task send_feature; integer i; reg [7:0] x; begin
  for(i=0;i<=161;i=i+1) begin x=0; if(i>=6&&i<=11) x=8'h10+i;if(i==12)x=8'h08;if(i==13)x=8'h00;if(i==23)x=17; if(i==26)x=192;if(i==27)x=168;if(i==28)x=1;if(i==29)x=9;if(i==34)x=8'hD6;if(i==35)x=8'hDB;if(i==36)x=8'hD6;if(i==37)x=8'hDA;
   if(i==42)x="F";if(i==43)x="T";if(i==44)x="R";if(i==45)x="2";if(i==46)x=8'h78;if(i==47)x=8'h56;if(i==48)x=8'h34;if(i==49)x=8'h12;if(i>=50)x=i-50;put(x,i==0);end
 end endtask
 task send_mod; input [7:0] op; integer i; reg [7:0] x; begin
  for(i=0;i<=57;i=i+1) begin x=0;if(i==12)x=8'h08;if(i==13)x=8'h00;if(i==23)x=17;if(i==26)x=192;if(i==27)x=168;if(i==28)x=1;if(i==29)x=9;if(i==34)x=8'hD6;if(i==35)x=8'hDB;if(i==36)x=8'hD6;if(i==37)x=8'hDA;
   if(i==42)x="M";if(i==43)x="O";if(i==44)x="D";if(i==45)x="1";if(i==46)x=op;if(i==47)x=8'h03;if(i==48)x=8'h00;if(i>=49&&i<=56)x=i-49;put(x,i==0);end
 end endtask
 initial begin #25;rst_n=1;send_feature();repeat(3)@(posedge clk);if(accepted!==32'd1||seq!==32'h12345678||features[31:0]!==32'h03020100||!peer_valid||!udp_seen) begin $display("accepted=%0d seq=%h f0=%h peer=%b seen=%b",accepted,seq,features[31:0],peer_valid,udp_seen);$fatal(1,"FTR2 decode failed");end send_mod(1);send_mod(2);repeat(2)@(posedge clk);if(words!==16'd1||waddr!==12'h003||wdata!==64'h0706050403020100)$fatal(1,"MOD1 field decode failed words=%0d addr=%h data=%h",words,waddr,wdata);send_mod(2);repeat(2)@(posedge clk);if(words!==16'd1)$fatal(1,"MOD1 duplicate address was counted twice");$display("LAN_PROTOCOL_PASS seq=%h words=%0d addr=%h data=%h",seq,words,waddr,wdata);$finish;end
endmodule
