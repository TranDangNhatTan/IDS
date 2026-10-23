`timescale 1ns/1ps
module uart_tx_sync #(parameter integer CLKS_PER_BIT=434)(input wire clk,input wire rst_n,input wire start,input wire [7:0] data,output reg tx,output reg busy,output reg done);
  reg [15:0] count; reg [3:0] bit_index; reg [7:0] shift;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin tx<=1;busy<=0;done<=0;count<=0;bit_index<=0;shift<=0;end
    else begin done<=0; if(!busy) begin tx<=1;count<=0;bit_index<=0;if(start)begin shift<=data;tx<=0;busy<=1;end end
    else if(count==CLKS_PER_BIT-1) begin count<=0;if(bit_index<8)begin tx<=shift[bit_index];bit_index<=bit_index+1'b1;end else if(bit_index==8)begin tx<=1;bit_index<=9;end else begin tx<=1;busy<=0;done<=1;end end else count<=count+1'b1; end
  end
endmodule
