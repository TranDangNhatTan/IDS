create_clock -name sys_clk_50 -period 20.000 [get_ports {sys_clk_50}]
# RX clock is recovered by the RTL8211F at 25 MHz after 100BASE-TX negotiates.
# TX logic uses the user-generated 25 MHz PLL clock; mailbox handoff uses
# two synchronizer flops.
create_clock -name eth_rgmii_rx_clk -period 40.000 [get_ports {eth_rgmii_rx_clk}]
# Name both PLL outputs explicitly.  Without these declarations Gowin assigns
# long auto-generated names that cannot be referenced while parsing this SDC.
create_clock -name pll_clk_25 -period 40.000 [get_pins {u_eth_rgmii_pll/u_pll/PLLA_inst/CLKOUT0}]
create_clock -name pll_txclk_25 -period 40.000 [get_pins {u_eth_rgmii_pll/u_pll/PLLA_inst/CLKOUT1}]
# The PHY-recovered RX clock has no fixed phase relationship to the 50 MHz
# oscillator or its 25 MHz PLL outputs.  Crossings use a two-flop toggle
# synchronizer and a stable mailbox payload; do not time them as synchronous.
set_clock_groups -asynchronous -group [get_clocks {sys_clk_50}] -group [get_clocks {pll_clk_25 pll_txclk_25}] -group [get_clocks {eth_rgmii_rx_clk}]
