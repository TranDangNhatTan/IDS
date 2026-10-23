`timescale 1ns/1ps
// GW5A PLL IP: 50 MHz input -> 25 MHz RGMII transmit reference clock.
// Simulation has a small behavioural model; hardware uses the IP generated
// by Gowin IP Core Generator in src/gowin_pll/.
module gowin_pll_50m_to_25m(
 input wire clk_in,
 input wire reset,
 output wire clk_25m,
 output wire lock
);
`ifdef SIMULATION
 reg clk_div = 1'b0;
 reg [3:0] lock_count = 4'd0;
 always @(posedge clk_in or posedge reset) begin
   if (reset) begin clk_div <= 1'b0; lock_count <= 4'd0; end
   else begin
     clk_div <= ~clk_div;
     if (!(&lock_count)) lock_count <= lock_count + 1'b1;
   end
 end
 assign clk_25m = clk_div;
 assign lock = &lock_count;
`else
 // The generated IP uses mdclk for its internal calibration sequencer.  It
 // must be connected to a running stable clock, even though mDRP is disabled.
 gowin_pll_25m pll_ip (
   .clkin(clk_in), .clkout0(clk_25m), .lock(lock), .mdclk(clk_in)
 );
`endif
endmodule
