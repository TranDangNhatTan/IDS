set_device -device_version B GW5A-LV25UG324C2/I1
foreach f {uart_rx_sync uart_tx_sync cobs_frame_rx_v2 cobs_frame_tx_v2 model_manager_v2 tree_model_dual_bram_v2 tree_engine_v2 top_pi_uart_ids} {add_file -type verilog "src/$f.v"}
foreach f {ids_node_decoder ids_feature_regfile} {add_file -type verilog "../../ip_final/src/deps/$f.v"}
add_file -type cst constraints/pi_uart_ids.cst
add_file -type sdc constraints/pi_uart_ids.sdc
set_option -top_module top_pi_uart_ids
set_option -output_base_name pi_uart_ids
set_option -verilog_std v2001
run all
