`timescale 1ns/1ps
// 100 Mb/s RGMII serializer.  At 100 Mb/s the PHY samples the nibble on the
// falling edge of the 25 MHz TX clock.  Drive ordinary fabric output registers
// on each rising edge so each nibble is stable for the following falling edge.
// This is the same reduced-speed transmit method used by the working ACG525
// demo; using an ODDRC here introduced a device-specific extra pipeline delay
// on the data/control pins relative to the board TX clock.
module rgmii_tx_byte(
 input wire clk,input wire rst_n,input wire [7:0] byte_data,input wire byte_valid,
 output wire byte_ready,output wire [3:0] txd,output wire tx_ctl
);
 reg high_nibble;reg [7:0] held_byte;reg held_valid;
 reg [3:0] txd_r;reg tx_ctl_r;
 assign byte_ready=!high_nibble;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   high_nibble<=0;held_byte<=0;held_valid<=0;txd_r<=0;tx_ctl_r<=0;
  end else if(!high_nibble)begin
   held_byte<=byte_data;held_valid<=byte_valid;
   txd_r<=byte_data[3:0];tx_ctl_r<=byte_valid;
   high_nibble<=1;
  end else begin
   txd_r<=held_byte[7:4];tx_ctl_r<=held_valid;
   high_nibble<=0;
  end
 assign txd=txd_r;assign tx_ctl=tx_ctl_r;
endmodule
