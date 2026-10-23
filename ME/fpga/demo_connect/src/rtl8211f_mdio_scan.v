`timescale 1ns/1ps
// Clause-22 MDIO read-only scanner.  It reads PHY identifier register 2 at
// addresses 0..7; it never writes a PHY register, so it is safe for bring-up.
module rtl8211f_mdio_scan #(
 parameter integer MDC_HALF_PERIOD = 25,
 // Let the RTL8211F finish its internal post-reset initialization before a
 // management transaction.  1 s at 50 MHz is intentionally conservative.
 parameter integer START_DELAY = 50000000
) (
 input wire clk,input wire rst_n,input wire mdio_in,
 output reg mdc,output reg mdio_out,output reg mdio_oe,
 output reg scan_done,output reg phy_found,output reg [4:0] found_addr,
 output reg [15:0] found_id1
);
 reg [31:0] delay_count;
 reg [15:0] divider;
 reg [5:0] bit_count;
 reg [2:0] scan_addr;
 reg active, ta_ok;
 reg [15:0] id_shift;
 reg [45:0] header;

 function [45:0] read_header;
  input [4:0] phy_addr;
  begin
   // preamble, start=01, read opcode=10, PHY address, register 2 (PHYID1)
   read_header={32'hffff_ffff,2'b01,2'b10,phy_addr,5'h02};
  end
 endfunction

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   delay_count<=0;divider<=0;bit_count<=0;scan_addr<=0;active<=0;ta_ok<=0;id_shift<=0;header<=0;
   mdc<=0;mdio_out<=1;mdio_oe<=0;scan_done<=0;phy_found<=0;found_addr<=0;found_id1<=0;
  end else if(!scan_done) begin
   if(delay_count<START_DELAY) delay_count<=delay_count+1'b1;
   else if(!active) begin
    header<=read_header({2'b00,scan_addr});
    bit_count<=0;id_shift<=0;ta_ok<=0;mdio_out<=1;mdio_oe<=1;mdc<=0;divider<=0;active<=1;
   end else if(divider==MDC_HALF_PERIOD-1) begin
    divider<=0;
    if(!mdc) begin
     mdc<=1;
     // TA[1] is a released cycle; PHY must drive TA[0] low at cycle 47.
     if(bit_count==6'd47) ta_ok<=~mdio_in;
     if(bit_count>=6'd48) id_shift<={id_shift[14:0],mdio_in};
    end else begin
     mdc<=0;
     if(bit_count==6'd63) begin
      active<=0;mdio_oe<=0;found_id1<=id_shift;
      if(ta_ok && id_shift!=16'h0000 && id_shift!=16'hffff) begin
       phy_found<=1;found_addr<={2'b00,scan_addr};
      end
      if(scan_addr==3'd7) scan_done<=1;
      else scan_addr<=scan_addr+1'b1;
     end else begin
      bit_count<=bit_count+1'b1;
      // Release MDIO before the two turnaround cycles (next index 46).
      if(bit_count>=6'd45) mdio_oe<=0;
      else mdio_out<=header[44-bit_count];
     end
    end
   end else divider<=divider+1'b1;
  end
 end
endmodule
