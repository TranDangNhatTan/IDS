create_clock -name sys_clk_50 -period 20.000 [get_ports {sys_clk_50}]
create_clock -name lan_rmii_ref_clk -period 20.000 [get_ports {lan_rmii_ref_clk}]
create_clock -name eth_rgmii_rx_clk -period 40.000 [get_ports {eth_rgmii_rx_clk}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk_50}] -group [get_clocks {lan_rmii_ref_clk}] -group [get_clocks {eth_rgmii_rx_clk}]
