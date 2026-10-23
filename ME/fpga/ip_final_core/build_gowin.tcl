set_device -device_version B GW5A-LV25UG324C2/I1
# Phase 1: generated 50-to-125 MHz PLL and onboard-RGMII clock/reset bring-up.
add_file -type verilog "src/ip/eth_rgmii_pll/eth_rgmii_pll.v"
add_file -type verilog "src/ip/eth_rgmii_pll/eth_rgmii_pll_mod.v"
add_file -type verilog "src/pll_init.v"
add_file -type verilog "src/rgmii_rx_byte.v"
add_file -type verilog "src/rgmii_tx_byte.v"
add_file -type verilog "src/uart_tx_byte.v"
add_file -type verilog "src/ids_uart_trace.v"
add_file -type verilog "src/ids_udp_feature_rx.v"
add_file -type verilog "src/ids_udp_reply_tx.v"
add_file -type verilog "src/ids_lan_trace_tx.v"
add_file -type verilog "src/ids_top_live.v"
add_file -type verilog "src/ids_tree_engine_live.v"
add_file -type verilog "src/ids_tree_rom_banked.v"
add_file -type verilog "src/deps/ids_node_decoder.v"
add_file -type verilog "src/deps/ids_feature_regfile.v"
add_file -type verilog "src/deps/ids_feature_quantizer.v"
add_file -type verilog "src/deps/ids_feature_ingest.v"
add_file -type verilog "src/top_acg525_ids_core.v"
add_file -type cst "src/ip_final_core.cst"
add_file -type sdc "src/ip_final_core.sdc"
set_option -top_module top_acg525_ids_core
set_option -output_base_name ip_final_core
set_option -verilog_std v2001
run all
