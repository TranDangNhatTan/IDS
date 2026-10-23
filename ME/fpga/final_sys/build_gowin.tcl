set_device -device_version B GW5A-LV25UG324C2/I1
foreach f {uart_rx_sync uart_tx_sync feature_frame_rx result_frame_tx top_final_sys} { add_file -type verilog "src/$f.v" }
foreach f {model_update_uart ids_tree_rom_banked ids_tree_engine_live} { add_file -type verilog "../ip_final/src/$f.v" }
foreach f {ids_node_decoder ids_feature_regfile} { add_file -type verilog "../ip_final/src/deps/$f.v" }
add_file -type cst "constraints/final_sys.cst"
add_file -type sdc "constraints/final_sys.sdc"
set_option -top_module top_final_sys
set_option -output_base_name final_sys
set_option -verilog_std v2001
run all
