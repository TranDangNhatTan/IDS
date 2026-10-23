set_device -device_version B GW5A-LV25UG324C2/I1
add_file -type verilog "src/uart_rx.v"
add_file -type verilog "src/uart_tx.v"
add_file -type verilog "src/uart_forwarder.v"
add_file -type cst "constraints/acg525.cst"
add_file -type sdc "constraints/acg525.sdc"
set_option -top_module uart_forwarder
set_option -output_base_name uart_forwarder
set_option -verilog_std v2001
run all
