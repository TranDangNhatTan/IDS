`timescale 1ns/1ps
module tb_rgmii_tx_byte;
 reg clk=0,rst_n=0;reg [7:0] byte_data=0;reg byte_valid=0;
 wire byte_ready;wire [3:0] txd;wire tx_ctl;
 reg [3:0] edge_data[0:15];reg edge_ctl[0:15];integer edge_count=0;
 always #10 clk=~clk;
 rgmii_tx_byte dut(.clk(clk),.rst_n(rst_n),.byte_data(byte_data),.byte_valid(byte_valid),.byte_ready(byte_ready),.txd(txd),.tx_ctl(tx_ctl));
 always @(posedge clk) if(rst_n)begin #2;if(tx_ctl)begin edge_data[edge_count]=txd;edge_ctl[edge_count]=tx_ctl;edge_count=edge_count+1;end end
 always @(negedge clk) if(rst_n)begin #2;if(tx_ctl)begin edge_data[edge_count]=txd;edge_ctl[edge_count]=tx_ctl;edge_count=edge_count+1;end end
 task offer;input [7:0] b;begin
  byte_data=b;byte_valid=1;wait(byte_ready);
  @(posedge clk);#3;byte_valid=0;
 end endtask
 initial begin
  repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
  offer(8'hA5);wait(byte_ready);repeat(2)@(posedge clk);#3;
  if(edge_count<4)$fatal(1,"too few DDR edges: %0d",edge_count);
  if(edge_data[0]!==4'h5||edge_data[1]!==4'h5||edge_data[2]!==4'hA||edge_data[3]!==4'hA)$fatal(1,"RGMII TX DDR mismatch %x %x %x %x",edge_data[0],edge_data[1],edge_data[2],edge_data[3]);
  if(!edge_ctl[0]||!edge_ctl[1]||!edge_ctl[2]||!edge_ctl[3])$fatal(1,"TX_CTL missing");
  $display("RGMII_DDR_TX_PASS edges=%x%x%x%x",edge_data[0],edge_data[1],edge_data[2],edge_data[3]);$finish;
 end
endmodule
