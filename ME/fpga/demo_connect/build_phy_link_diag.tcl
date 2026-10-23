set_device -device_version B GW5A-LV25UG324C2/I1
add_file -type verilog "src/top_phy_link_diag.v"
add_file -type cst "src/demo_connect_onboard.cst"
add_file -type sdc "src/phy_link_diag.sdc"
set_option -top_module top_phy_link_diag
set_option -output_base_name phy_link_diag
set_option -verilog_std v2001
run all
