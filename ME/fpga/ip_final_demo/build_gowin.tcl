set_device -device_version B GW5A-LV25UG324C2/I1
foreach f {reset_sync rtl8211f_mdio_init rmii_deserializer rmii_serializer async_packet_fifo rgmii_100_deserializer rgmii_100_serializer uart_tx_byte uart_debug_reporter top_acg525_rgmii_rmii_bridge} { add_file -type verilog "src/deps/$f.v" }
foreach f {ids_node_decoder ids_feature_regfile ids_rate_quantizer ids_feature_quantizer ids_feature_ingest ids_packet_parser ids_history_window_bram} { add_file -type verilog "src/deps/$f.v" }
foreach f {uart_rx_byte model_update_uart ids_tree_rom_banked ids_tree_engine_live ids_top_live ids_flow_table_resource ids_history_pipeline_resource ids_packet_top_resource ids_uart_telemetry top_acg525_inline_ids} { add_file -type verilog "src/$f.v" }
add_file -type cst "src/ip_final_demo.cst"
add_file -type sdc "src/ip_final_demo.sdc"
set_option -top_module top_acg525_inline_ids
set_option -output_base_name ip_final_demo
set_option -verilog_std v2001
run all

