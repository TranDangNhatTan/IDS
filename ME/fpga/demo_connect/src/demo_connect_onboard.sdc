create_clock -name sys_clk_50 -period 20.000 [get_ports {sys_clk_50}]
create_clock -name rgmii_rx_clk_100m -period 40.000 [get_ports {eth_rgmii_rx_clk}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk_50}] -group [get_clocks {rgmii_rx_clk_100m}]
