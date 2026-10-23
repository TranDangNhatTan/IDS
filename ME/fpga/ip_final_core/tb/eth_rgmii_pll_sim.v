// Simulation-only replacement for Gowin PLLA.  Hardware builds use the IP
// under src/ip/eth_rgmii_pll; Icarus does not provide the vendor PLLA model.
module eth_rgmii_pll(input wire clkin,output wire clkout0,output wire clkout1,
 output wire lock,input wire mdclk);
 assign clkout0=clkin;
 assign clkout1=clkin;
 assign lock=1'b1;
endmodule
