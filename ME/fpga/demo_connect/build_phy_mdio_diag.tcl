set_device -device_version B GW5A-LV25UG324C2/I1
foreach f {pll_init rgmii_100_deserializer rgmii_frame_adapter rtl8211f_mdio_init udp_ping_rx gowin_pll_50m_to_25m rgmii_100_ack_tx_pll top_acg525_udp_echo top_acg525_phy_mdio_diag} { add_file -type verilog "src/$f.v" }
add_file -type verilog "src/gowin_pll/gowin_pll_25m.v"
add_file -type verilog "src/gowin_pll/gowin_pll_25m_mod.v"
add_file -type cst "src/demo_connect_onboard.cst"
add_file -type sdc "src/demo_connect_onboard.sdc"
set_option -top_module top_acg525_phy_mdio_diag
set_option -output_base_name phy_mdio_diag
set_option -verilog_std v2001
run all
