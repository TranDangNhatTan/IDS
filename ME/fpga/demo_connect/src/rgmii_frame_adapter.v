`timescale 1ns/1ps
// Remove the seven-byte Ethernet preamble and SFD emitted by the PHY and
// present a MAC-header-first byte stream to udp_ping_rx.
module rgmii_frame_adapter(
 input wire clk,input wire rst_n,input wire [7:0] rx_byte,
 input wire rx_valid,input wire rx_last,input wire rx_error,
 output reg [7:0] byte_data,output reg byte_valid,output reg byte_sop
);
 reg [3:0] prefix_count;
 reg data_started;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin prefix_count<=0;data_started<=0;byte_data<=0;byte_valid<=0;byte_sop<=0;end
  else begin
   byte_valid<=0;byte_sop<=0;
   if(rx_valid) begin
    if(prefix_count<8) prefix_count<=prefix_count+1'b1;
    else begin
     byte_data<=rx_byte;byte_valid<=1;
     if(!data_started) begin byte_sop<=1;data_started<=1;end
    end
    if(rx_last||rx_error) begin prefix_count<=0;data_started<=0;end
   end else if(rx_error) begin prefix_count<=0;data_started<=0;end
  end
 end
endmodule
