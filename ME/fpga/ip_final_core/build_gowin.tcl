set_device -device_version B GW5A-LV25UG324C2/I1
foreach f {rmii_deserializer rmii_serializer ids_node_decoder ids_feature_regfile ids_feature_quantizer ids_feature_ingest} { add_file -type verilog "src/deps/$f.v" }
foreach f {ids_tree_rom_banked ids_tree_engine_live ids_top_live ids_udp_feature_rx ids_udp_reply_tx top_acg525_ids_core} { add_file -type verilog "src/$f.v" }
add_file -type cst "src/ip_final_core.cst"
add_file -type sdc "src/ip_final_core.sdc"
set_option -top_module top_acg525_ids_core
set_option -output_base_name ip_final_core
set_option -verilog_std v2001
run all
