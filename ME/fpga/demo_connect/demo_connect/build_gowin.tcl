add_file -type verilog "src/reset_sync.v"
add_file -type verilog "src/rtl8211f_mdio_init.v"
add_file -type verilog "src/rmii_deserializer.v"
add_file -type verilog "src/rmii_serializer.v"
add_file -type verilog "src/async_packet_fifo.v"
add_file -type verilog "src/rgmii_100_deserializer.v"
add_file -type verilog "src/rgmii_100_serializer.v"
add_file -type verilog "src/uart_tx_byte.v"
add_file -type verilog "src/uart_debug_reporter.v"
add_file -type verilog "src/top_acg525_rgmii_rmii_bridge.v"
add_file -type cst "src/demo_connect.cst"
add_file -type sdc "src/bridge_clocks.sdc"

set_device -device_version B GW5A-LV25UG324C2/I1
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_acg525_rgmii_rmii_bridge
set_option -output_base_name demo_connect_release
set_option -verilog_std v2001
run all
