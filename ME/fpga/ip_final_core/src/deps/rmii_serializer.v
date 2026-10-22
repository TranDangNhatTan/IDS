`timescale 1ns/1ps
// RMII transmitter. Bytes are emitted least-significant dibit first.
module rmii_serializer (
 input wire clk,input wire rst_n,input wire [7:0] byte_data,input wire byte_valid,
 output wire byte_ready,output reg [1:0] txd,output reg tx_en
);
 reg busy; reg [1:0] dibit; reg [7:0] shift;
 assign byte_ready=!busy || (dibit==2'd3);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin busy<=0;dibit<=0;shift<=0;txd<=0;tx_en<=0;end
  else if(!busy) begin
   if(byte_valid) begin busy<=1;dibit<=0;shift<=byte_data;txd<=byte_data[1:0];tx_en<=1;end
   else begin txd<=0;tx_en<=0;end
  end else if(dibit==2'd3) begin
   if(byte_valid) begin shift<=byte_data;dibit<=0;txd<=byte_data[1:0];tx_en<=1;end
   else begin busy<=0;dibit<=0;txd<=0;tx_en<=0;end
  end else begin shift<={2'b00,shift[7:2]};dibit<=dibit+1'b1;txd<=shift[3:2];tx_en<=1;end
 end
endmodule
