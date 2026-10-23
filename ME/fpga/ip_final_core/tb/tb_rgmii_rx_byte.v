`timescale 1ns/1ps
module tb_rgmii_rx_byte;
 reg clk=0,rst_n=0,ctl=0; reg [3:0] rxd=0;
 wire [7:0] data; wire valid,sop,last,err;
 integer count=0; reg [7:0] captured[0:7];
 rgmii_rx_byte dut(.rx_clk(clk),.rst_n(rst_n),.sample_ce(1'b1),.rxd(rxd),.rx_ctl(ctl),
  .byte_data(data),.byte_valid(valid),.byte_sop(sop),.byte_last(last),.frame_error(err));
 always #10 clk=~clk;

 // 100M RGMII repeats each MII nibble on both clock edges. Low and high
 // nibbles therefore occupy two successive 25 MHz clock periods.
 task send_ddr_byte; input [7:0] b; begin
  @(posedge clk); #1 rxd=b[3:0];ctl=1;
  @(posedge clk); #1 rxd=b[7:4];ctl=1;
 end endtask
 task end_frame; begin
  @(posedge clk); #1 ctl=0;rxd=0;
  repeat(6) @(posedge clk);
 end endtask
 always @(posedge clk) #2 if(valid) begin
  captured[count]=data;
  if(sop!==((count==0)?1'b1:1'b0)) $fatal(1,"unexpected SOP at byte %0d",count);
  count=count+1;
 end
 initial begin
  repeat(3) @(posedge clk);rst_n=1;
  repeat(7) send_ddr_byte(8'h55);send_ddr_byte(8'hD5);
  send_ddr_byte(8'hDA);send_ddr_byte(8'h7A);send_ddr_byte(8'h00);send_ddr_byte(8'h11);
  end_frame();
  if(err) $fatal(1,"RGMII receiver flagged error");
  if(count!=4 || captured[0]!==8'hDA || captured[1]!==8'h7A || captured[2]!==8'h00 || captured[3]!==8'h11)
   $fatal(1,"DDR byte recovery failed count=%0d bytes=%h %h %h %h",count,captured[0],captured[1],captured[2],captured[3]);
  $display("RGMII_DDR_RX_PASS count=%0d header=%h%h%h%h",count,captured[0],captured[1],captured[2],captured[3]);
  $finish;
 end
endmodule
