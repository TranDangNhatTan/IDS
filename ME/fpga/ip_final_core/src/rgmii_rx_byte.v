`timescale 1ns/1ps
// ACG525 RTL8211F 100BASE-TX RGMII receiver.
// At 100 Mb/s RX_CLK is 25 MHz and a MII nibble is held for one complete
// clock period. This follows demo_connect's physically verified receiver:
// reconstruct bytes first, then remove the Ethernet preamble and SFD.
module rgmii_rx_byte(
 input wire rx_clk,input wire rst_n,input wire sample_ce,input wire [3:0] rxd,input wire rx_ctl,
 output reg [7:0] byte_data,output reg byte_valid,output reg byte_sop,
 output reg byte_last,output reg frame_error
);
 // At 100 Mb/s the RTL8211F repeats each MII nibble on both RGMII edges.
 // Capture the falling edge in the dedicated input DDR cells: it is in the
 // middle of the nibble eye and removes the placement-dependent pad-to-fabric
 // delay that made payload bytes intermittently fail while headers survived.
 wire [3:0] rxd_rise,rxd_fall;
 wire ctl_rise,ctl_fall;
 genvar rx_bit;
 generate for(rx_bit=0;rx_bit<4;rx_bit=rx_bit+1) begin: rx_iddr
  IDDR rx_data_iddr(.Q0(rxd_rise[rx_bit]),.Q1(rxd_fall[rx_bit]),.D(rxd[rx_bit]),.CLK(rx_clk));
 end endgenerate
 IDDR rx_ctl_iddr(.Q0(ctl_rise),.Q1(ctl_fall),.D(rx_ctl),.CLK(rx_clk));
 wire [3:0] sampled_rxd=rxd_fall;
 wire sampled_ctl=ctl_fall;
 reg in_frame,high_nibble;
 reg [3:0] low_nibble;
 reg [7:0] pending_byte;
 reg pending_valid;
 reg [7:0] phy_byte;
 reg phy_valid,phy_last,phy_error;
 reg [2:0] idle_count;

 // Preserve the final byte until RX_CTL falls so it is not lost at EoF.
 always @(posedge rx_clk or negedge rst_n) begin
  if(!rst_n) begin
   in_frame<=0;high_nibble<=0;low_nibble<=0;pending_byte<=0;pending_valid<=0;
   phy_byte<=0;phy_valid<=0;phy_last<=0;phy_error<=0;idle_count<=0;
  end else begin
   phy_valid<=0;phy_last<=0;phy_error<=0;
   if(!in_frame||sampled_ctl) idle_count<=0;
   else if(idle_count!=3'd7) idle_count<=idle_count+1'b1;
   if(sample_ce && sampled_ctl) begin
    in_frame<=1;
    if(!high_nibble) begin
     low_nibble<=sampled_rxd;high_nibble<=1;
    end else begin
     if(pending_valid) begin phy_byte<=pending_byte;phy_valid<=1;end
     pending_byte<={sampled_rxd,low_nibble};pending_valid<=1;high_nibble<=0;
    end
   // RX_CTL is DDR-encoded and the 50 MHz synchronizer may expose a single
   // low sample inside an otherwise valid frame.  Ethernet's real interframe
   // gap is much longer, so require four consecutive low system-clock samples
   // before closing the frame.  This preserves SOP/last without concatenating
   // adjacent packets or chopping a packet at a DDR half-cycle.
   end else if(in_frame && idle_count==3'd3) begin
    in_frame<=0;
    idle_count<=0;
    if(high_nibble) begin
     high_nibble<=0;pending_valid<=0;phy_error<=1;
    end else if(pending_valid) begin
     phy_byte<=pending_byte;phy_valid<=1;phy_last<=1;pending_valid<=0;
    end
   end
  end
 end

 reg [3:0] prefix_count;
 reg data_started;
 // Remove 7 x 0x55 plus the 0xD5 SFD. The protocol parser consequently
 // receives destination-MAC at index 0 on every frame.
 always @(posedge rx_clk or negedge rst_n) begin
  if(!rst_n) begin
   prefix_count<=0;data_started<=0;byte_data<=0;byte_valid<=0;byte_sop<=0;
   byte_last<=0;frame_error<=0;
  end else begin
   byte_valid<=0;byte_sop<=0;byte_last<=0;frame_error<=phy_error;
   if(phy_valid) begin
    if(prefix_count<4'd8) prefix_count<=prefix_count+1'b1;
    else begin
     byte_data<=phy_byte;byte_valid<=1;
     if(!data_started) begin byte_sop<=1;data_started<=1;end
     if(phy_last) byte_last<=1;
    end
    if(phy_last) begin prefix_count<=0;data_started<=0;end
   end else if(phy_error) begin
    prefix_count<=0;data_started<=0;
   end
  end
 end
endmodule
