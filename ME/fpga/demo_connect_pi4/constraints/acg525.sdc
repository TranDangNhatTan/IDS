create_clock -name sys_clk_50 -period 20.000 [get_ports {clk}]

# uart_rx_pi is asynchronous and is synchronized by two flip-flops in uart_rx.
# No broad false path is used, so the synchronizer chain remains timed.
