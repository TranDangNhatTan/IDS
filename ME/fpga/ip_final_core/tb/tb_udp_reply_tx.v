`timescale 1ns/1ps
module tb_udp_reply_tx;
 reg clk=0,rst_n=0,peer_valid=1,result_valid=0,model_ack=0,model_ready=0; reg [47:0] peer_mac=48'h001122334455; reg [31:0] peer_ip=32'hC0A80109,seq=32'h12345678,accepted=5,dropped=0; reg [15:0] peer_port=16'hD6DB,version=1,words=0; reg [5:0] cls=16;reg [11:0] leaf=12'h123;reg [7:0] steps=8'h07;reg [2:0] err=0;
 wire [1:0] txd;wire tx_en;wire result_sent,tx_error; integer dc=0,bc=0; reg [7:0] byte_acc; reg [7:0] bytes[0:100];
 ids_udp_reply_tx dut(.clk(clk),.rst_n(rst_n),.peer_valid(peer_valid),.peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.result_valid(result_valid),.record_sequence(seq),.class_id(cls),.leaf_node(leaf),.step_count(steps),.error_code(err),.model_version(version),.model_ack(model_ack),.model_ready(model_ready),.accepted_words(words),.accepted_records(accepted),.dropped_records(dropped),.lan_txd(txd),.lan_tx_en(tx_en),.result_sent(result_sent),.tx_error(tx_error));
 always #10 clk=~clk;
 always @(posedge clk) #1 if(tx_en) begin byte_acc[dc*2 +:2]=txd;dc=dc+1;if(dc==4)begin bytes[bc]=byte_acc;bc=bc+1;dc=0;end end
 initial begin #25;rst_n=1;@(negedge clk);result_valid=1;@(negedge clk);result_valid=0;repeat(400)@(posedge clk);if(bc!=77||bytes[0]!=8'h55||bytes[6]!=8'h55||bytes[7]!=8'hD5||bytes[8]!=8'h00||bytes[20]!=8'h08||bytes[21]!=8'h00||bytes[50]!="I"||bytes[53]!="1"||bytes[54]!=8'h78||bytes[57]!=8'h12)$fatal(1,"UDP TX frame mismatch bytes=%0d",bc);$display("UDP_REPLY_TX_PASS bytes=%0d",bc);$finish;end
endmodule
