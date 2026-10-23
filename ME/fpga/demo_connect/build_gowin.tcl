set_device -device_version B GW5A-LV25UG324C2/I1
# Stable hardware-link image only. It does not use the experimental MDIO
# state machines or the former 25 MHz RGMII/UDP implementation.
foreach f {pll_init gowin_pll/gowin_pll_125m gowin_pll/gowin_pll_125m_mod top_acg525_gigabit_clock_diag} { add_file -type verilog "src/$f.v" }
add_file -type cst "src/demo_connect_onboard.cst"
add_file -type sdc "src/demo_connect_onboard.sdc"
set_option -top_module top_acg525_gigabit_clock_diag
set_option -output_base_name demo_connect
set_option -verilog_std v2001
run all
