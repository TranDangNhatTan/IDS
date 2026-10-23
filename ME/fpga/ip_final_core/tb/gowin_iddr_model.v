`timescale 1ns/1ps
// Functional model used only by Icarus testbenches.  Gowin synthesis maps the
// identically named primitive in rgmii_rx_byte.v to the GW5A input DDR cell.
module IDDR(output reg Q0,output reg Q1,input wire D,input wire CLK);
 initial begin Q0=1'b0;Q1=1'b0;end
 always @(posedge CLK) Q0<=D;
 always @(negedge CLK) Q1<=D;
endmodule
