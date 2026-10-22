`timescale 1ns/1ps
// Production-demo top: verified L2 bridge plus a non-blocking RMII monitor path.
// Machine A is attached to LAN8720/RMII; its A->B frames are classified.
module top_acg525_inline_ids (
 input wire sys_clk_50,input wire ext_rst_n,
 input wire lan_rmii_ref_clk,input wire [1:0] lan_rxd,input wire lan_crs_dv,output wire [1:0] lan_txd,output wire lan_tx_en,
 input wire eth_rgmii_rx_clk,input wire [3:0] eth_rgmii_rxd,input wire eth_rgmii_rx_ctl,output wire eth_rgmii_tx_clk,output wire [3:0] eth_rgmii_txd,output wire eth_rgmii_tx_ctl,output wire eth_rst_n,output wire eth_mdc,inout wire eth_mdio,
 input wire uart_rx,output wire uart_tx,output wire [3:0] led
);
 wire bridge_uart_unused; wire [3:0] bridge_led;
 // The known-good bridge remains the only owner of Ethernet TX pins.
 top_acg525_rgmii_rmii_bridge bridge(
  .sys_clk_50(sys_clk_50),.ext_rst_n(ext_rst_n),.lan_rmii_ref_clk(lan_rmii_ref_clk),.lan_rxd(lan_rxd),.lan_crs_dv(lan_crs_dv),.lan_txd(lan_txd),.lan_tx_en(lan_tx_en),
  .eth_rgmii_rx_clk(eth_rgmii_rx_clk),.eth_rgmii_rxd(eth_rgmii_rxd),.eth_rgmii_rx_ctl(eth_rgmii_rx_ctl),.eth_rgmii_tx_clk(eth_rgmii_tx_clk),.eth_rgmii_txd(eth_rgmii_txd),.eth_rgmii_tx_ctl(eth_rgmii_tx_ctl),.eth_rst_n(eth_rst_n),.eth_mdc(eth_mdc),.eth_mdio(eth_mdio),.uart_tx(bridge_uart_unused),.led(bridge_led));
 wire [7:0] monitor_byte; wire monitor_valid,monitor_last,monitor_error; reg monitor_prev_valid; wire monitor_sop=monitor_valid&&!monitor_prev_valid;
 rmii_deserializer monitor_rx(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rxd(lan_rxd),.crs_dv(lan_crs_dv),.rx_byte(monitor_byte),.rx_byte_valid(monitor_valid),.rx_byte_last(monitor_last),.rx_frame_error(monitor_error));
 always @(posedge lan_rmii_ref_clk or negedge ext_rst_n) if(!ext_rst_n) monitor_prev_valid<=0; else monitor_prev_valid<=monitor_valid;
 reg [63:0] timestamp; reg [25:0] timeout_counter; wire timeout_close=(timeout_counter==26'd49999999);
 always @(posedge lan_rmii_ref_clk or negedge ext_rst_n) if(!ext_rst_n) begin timestamp<=0;timeout_counter<=0;end else begin timestamp<=timestamp+64'd1;timeout_counter<=timeout_close?26'd0:timeout_counter+26'd1;end
 wire [7:0] uart_rx_data; wire uart_rx_valid; wire model_write_en,model_activate,checksum_error,update_open,model_ready; wire [11:0] model_write_addr; wire [63:0] model_write_data; wire [15:0] accepted_words;
 uart_rx_byte u_rx(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rx(uart_rx),.data(uart_rx_data),.valid(uart_rx_valid));
 wire busy,done,result_valid,parser_error,flow_table_full,close_event_overflow,active_bank; wire [5:0] class_id; wire [11:0] leaf_node; wire [2:0] error_code; wire [7:0] step_count; wire [15:0] model_version;
 model_update_uart updater(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rx_data(uart_rx_data),.rx_valid(uart_rx_valid),.engine_busy(busy),.write_en(model_write_en),.write_addr(model_write_addr),.write_data(model_write_data),.activate_pulse(model_activate),.checksum_error(checksum_error),.accepted_words(accepted_words),.update_open(update_open),.model_ready(model_ready));
 // ROM_FILE is retained only as an interface parameter. The live model RAM is
 // intentionally blank after configuration and is filled from UART.
 ids_packet_top_resource #(.TICKS_PER_SECOND(50000000),.ROM_FILE("model/node_rom.mem")) ids(
  .clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.rx_data(monitor_byte),.rx_valid(monitor_valid && !update_open && model_ready),.rx_sop(monitor_sop && !update_open && model_ready),.rx_last(monitor_last && !update_open && model_ready),.timestamp_ticks(timestamp),.timeout_close(timeout_close),.model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),.parser_error(parser_error),.flow_table_full(flow_table_full),.busy(busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version),.close_event_overflow(close_event_overflow));
 ids_uart_telemetry telemetry(.clk(lan_rmii_ref_clk),.rst_n(ext_rst_n),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.step_count(step_count),.active_bank(active_bank),.model_version(model_version),.parser_error(parser_error|monitor_error),.flow_table_full(flow_table_full),.error_code(error_code),.uart_tx(uart_tx));
 assign led={checksum_error|flow_table_full|close_event_overflow|parser_error,bridge_led[2:0]};
endmodule
