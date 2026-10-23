create_clock -name sys_clk_50 -period 20.000 [get_ports {clk}]

# uart_rx and rst_n are asynchronous inputs.  No broad false path is added:
# timing from synchronizer stage one to stage two remains fully analyzed.
