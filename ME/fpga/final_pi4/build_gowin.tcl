set_device -device_version B GW5A-LV25UG324C2/I1
add_file -type verilog "uart_rx.v"
add_file -type verilog "uart_rx_board_top.v"
add_file -type cst "acg525.cst"
add_file -type sdc "acg525.sdc"
set_option -top_module uart_rx_board_top
set_option -output_base_name final_pi4_uart_rx
set_option -verilog_std v2001
run all
