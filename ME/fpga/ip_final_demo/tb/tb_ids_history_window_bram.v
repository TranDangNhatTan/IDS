`timescale 1ns/1ps
module tb_ids_history_window_bram;
 reg clk=0,rst_n=0,commit=0,query_start=0;
 reg [31:0] commit_time=0,commit_dst=0,query_time=0,query_dst=0;
 reg [15:0] commit_port=0,query_port=0; reg [6:0] commit_service=0,query_service=0; reg [3:0] commit_flag=0;
 wire commit_ready,busy,result_valid; wire [19*32-1:0] features;
 ids_history_window_bram #(.HISTORY_DEPTH(4)) dut(
  .clk(clk),.rst_n(rst_n),.commit(commit),.commit_timestamp_seconds(commit_time),.commit_dst_ip(commit_dst),.commit_src_port(commit_port),.commit_service_code(commit_service),.commit_flag_code(commit_flag),
  .query_start(query_start),.query_timestamp_seconds(query_time),.query_dst_ip(query_dst),.query_src_port(query_port),.query_service_code(query_service),.commit_ready(commit_ready),.busy(busy),.result_valid(result_valid),.history_features_flat(features));
 always #5 clk=~clk;
 task add_entry; input [31:0] t; input [31:0] d; input [15:0] p; input [6:0] s; input [3:0] f; begin
  @(negedge clk); commit_time=t;commit_dst=d;commit_port=p;commit_service=s;commit_flag=f;commit=1;
  @(negedge clk); commit=0;
 end endtask
 initial begin
  repeat(2) @(negedge clk); rst_n=1;
  add_entry(100,32'hC0A83202,16'd1234,7'd25,4'd6);
  add_entry(101,32'hC0A83202,16'd1234,7'd25,4'd0);
  @(negedge clk); query_time=102;query_dst=32'hC0A83202;query_port=1234;query_service=25;query_start=1;
  @(negedge clk); query_start=0;
  wait(result_valid); #1;
  if(features[0*32 +:32] != 2 || features[1*32 +:32] != 2 || features[9*32 +:32] != 2 || features[10*32 +:32] != 2) $fatal(1,"history counts incorrect");
  if(features[2*32 +:32] != 32768) $fatal(1,"serror rate incorrect: %0d",features[2*32 +:32]);
  $display("HISTORY_BRAM_PASS cycles=8 time_count=%0d",features[0*32 +:32]);
  $finish;
 end
endmodule

