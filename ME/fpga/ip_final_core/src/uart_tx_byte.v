`timescale 1ns/1ps
// 8-N-1 transmitter. 50 MHz / 434 = 115207 baud (0.006% error at 115200).
module uart_tx_byte #(parameter integer CLKS_PER_BIT=434)(
 input wire clk,input wire rst_n,input wire start,input wire [7:0] data,
 output reg tx,output reg busy,output reg done
);
 reg [15:0] ticks; reg [3:0] bit_index; reg [7:0] data_latched;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin tx<=1'b1;busy<=0;done<=0;ticks<=0;bit_index<=0;data_latched<=0;end
  else begin
   done<=0;
   if(!busy) begin
    tx<=1'b1;ticks<=0;bit_index<=0;
    if(start) begin data_latched<=data;tx<=1'b0;busy<=1'b1;end
   end else if(ticks==CLKS_PER_BIT-1) begin
    ticks<=0;
    if(bit_index<8) begin tx<=data_latched[bit_index];bit_index<=bit_index+1'b1;end
    else if(bit_index==8) begin tx<=1'b1;bit_index<=9;end
    else begin tx<=1'b1;busy<=0;done<=1'b1;end
   end else ticks<=ticks+1'b1;
  end
 end
endmodule
