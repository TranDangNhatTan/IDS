`timescale 1ns/1ps
module uart_rx_sync #(parameter integer CLKS_PER_BIT=434)(input wire clk,input wire rst_n,input wire rx,output reg [7:0] data,output reg valid,output reg framing_error);
  reg s0,s1; reg [1:0] state; reg [15:0] count; reg [2:0] bit_index;
  localparam IDLE=0,START=1,DATA=2,STOP=3;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin s0<=1; s1<=1; state<=IDLE; count<=0; bit_index<=0; data<=0; valid<=0; framing_error<=0; end
    else begin
      s0<=rx; s1<=s0; valid<=0;
      case(state)
        IDLE: if(!s1) begin count<=0; state<=START; end
        START: if(count==(CLKS_PER_BIT/2)-1) begin count<=0; if(s1) state<=IDLE; else begin bit_index<=0; state<=DATA; end end else count<=count+1'b1;
        DATA: if(count==CLKS_PER_BIT-1) begin count<=0; data[bit_index]<=s1; if(bit_index==7) state<=STOP; else bit_index<=bit_index+1'b1; end else count<=count+1'b1;
        STOP: if(count==CLKS_PER_BIT-1) begin count<=0; state<=IDLE; if(s1) valid<=1; else framing_error<=1; end else count<=count+1'b1;
      endcase
    end
  end
endmodule
