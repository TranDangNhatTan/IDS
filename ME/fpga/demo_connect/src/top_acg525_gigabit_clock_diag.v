`timescale 1ns/1ps
// Gigabit physical-link probe: reset RTL8211F then drive its RGMII GTX clock
// from the dedicated 125 MHz GW5A PLL. No MDIO and no Ethernet frame logic.
module top_acg525_gigabit_clock_diag(
 input wire sys_clk_50,input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,
 output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,
 output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,output wire [3:0] led
);
 localparam integer RESET_CYCLES=5_000_000;
 reg [22:0] rc=0;reg reset_done=0;reg [25:0] hb=0;
 always @(posedge sys_clk_50) begin hb<=hb+1'b1;if(!reset_done)begin if(rc==RESET_CYCLES-1)reset_done<=1;else rc<=rc+1'b1;end end
 wire pll_lock,tx_clk_125m;
 gowin_pll_125m pll(.clkin(sys_clk_50),.clkout0(tx_clk_125m),.lock(pll_lock),.mdclk(sys_clk_50));
 assign eth_rst_n=reset_done;
 assign eth_rgmii_tx_clk=(reset_done&&pll_lock)?tx_clk_125m:1'b0;
 assign eth_rgmii_txd=4'b0;assign eth_rgmii_tx_ctl=1'b0;assign eth_mdc=1'b0;assign eth_mdio=1'bz;
 // Measure the PLL output against exactly 0.4 s of the known 50 MHz input.
 // 125 MHz yields about 50,000,000 edges; the broad acceptance band allows
 // PLL lock settling and CDC sampling but rejects 25/50/100 MHz.
 reg [26:0] tx_edge_count=0;
 always @(posedge tx_clk_125m or negedge reset_done)
  if(!reset_done) tx_edge_count<=0; else tx_edge_count<=tx_edge_count+1'b1;
 reg [26:0] tx_s1=0,tx_s2=0;reg [24:0] measure_count=0;reg pll_125_verified=0;
 always @(posedge sys_clk_50 or negedge reset_done) begin
  if(!reset_done) begin tx_s1<=0;tx_s2<=0;measure_count<=0;pll_125_verified<=0;end
  else begin
   tx_s1<=tx_edge_count;tx_s2<=tx_s1;
   if(measure_count<25_000_000) measure_count<=measure_count+1'b1;
   else if(!pll_125_verified && tx_s2>27'd45_000_000 && tx_s2<27'd55_000_000) pll_125_verified<=1;
  end
 end
 // D0 heartbeat, D1 reset released, D2 PLL lock, D3 verified 125 MHz.
 assign led={pll_125_verified&hb[25],pll_lock&hb[25],reset_done&hb[25],hb[25]};
endmodule
