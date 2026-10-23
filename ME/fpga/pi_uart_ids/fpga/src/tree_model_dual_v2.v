`timescale 1ns/1ps
// Two volatile 1273x64 model images. Inference reads active_bank; upload writes
// its complement. Committing atomically flips the one-bit bank selector.
module tree_model_dual_v2 #(parameter NODE_COUNT=1273)(
 input wire clk,input wire [11:0] read_addr,output reg [63:0] read_data,
 input wire write_en,input wire [11:0] write_addr,input wire [63:0] write_data,
 input wire commit,input wire [15:0] commit_version,input wire rst_n,output reg active_bank,output reg [15:0] model_version
);
 reg [63:0] bank0[0:NODE_COUNT-1];reg [63:0] bank1[0:NODE_COUNT-1];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active_bank<=0;model_version<=0;read_data<=0;end else begin
   if(read_addr<NODE_COUNT)read_data<=active_bank?bank1[read_addr]:bank0[read_addr];else read_data<=64'hC000000000000000;
   if(write_en&&write_addr<NODE_COUNT)begin if(active_bank)bank0[write_addr]<=write_data;else bank1[write_addr]<=write_data;end
   if(commit)begin active_bank<=~active_bank;model_version<=commit_version;end
  end
 end
endmodule
