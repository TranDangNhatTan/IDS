module ids_packet_top_resource #(
 parameter TICKS_PER_SECOND=50000000, parameter ROM_FILE="model/node_rom.mem"
) (
 input wire clk,input wire rst_n,input wire [7:0] rx_data,input wire rx_valid,input wire rx_sop,input wire rx_last,
 input wire [63:0] timestamp_ticks,input wire timeout_close,
 input wire model_write_en,input wire [11:0] model_write_addr,input wire [63:0] model_write_data,input wire model_activate,
 output wire parser_error,output wire flow_table_full,output wire busy,output wire done,output wire result_valid,
 output wire [5:0] class_id,output wire [11:0] leaf_node,output wire [2:0] error_code,output wire [7:0] step_count,
 output wire active_bank,output wire [15:0] model_version,output wire close_event_overflow
);
 wire descriptor_valid; wire [31:0] src_ip,dst_ip; wire [15:0] src_port,dst_port,frame_bytes,ip_total_bytes;
 wire [7:0] ip_protocol,tcp_flags; wire [1:0] protocol_code; wire [6:0] service_code; wire [3:0] flag_code;
 wire wrong_fragment,urgent; wire [63:0] packet_timestamp; wire packet_ready;
 wire event_valid,event_ready; wire [9*32-1:0] base_features; wire [31:0] event_time,event_dst; wire [15:0] event_port; wire [6:0] event_service; wire [3:0] event_flag;
 wire raw_record_valid,raw_record_ready; wire [28*32-1:0] raw_features_flat;
 ids_packet_parser parser(.clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.rx_sop(rx_sop),.rx_last(rx_last),.timestamp_ticks(timestamp_ticks),.descriptor_valid(descriptor_valid),.descriptor_error(parser_error),.src_ip(src_ip),.dst_ip(dst_ip),.src_port(src_port),.dst_port(dst_port),.frame_bytes(frame_bytes),.ip_total_bytes(ip_total_bytes),.ip_protocol(ip_protocol),.tcp_flags(tcp_flags),.protocol_code(protocol_code),.service_code(service_code),.flag_code(flag_code),.wrong_fragment(wrong_fragment),.urgent(urgent),.packet_timestamp(packet_timestamp));
 ids_flow_table_resource #(.TICKS_PER_SECOND(TICKS_PER_SECOND),.FLOW_TIMEOUT_TICKS(5*TICKS_PER_SECOND)) flows(
  .clk(clk),.rst_n(rst_n),.packet_valid(descriptor_valid),.packet_ready(packet_ready),.src_ip(src_ip),.dst_ip(dst_ip),.src_port(src_port),.dst_port(dst_port),.frame_bytes(frame_bytes),.ip_protocol(ip_protocol),.tcp_flags(tcp_flags),.protocol_code(protocol_code),.service_code(service_code),.flag_code(flag_code),.wrong_fragment(wrong_fragment),.urgent(urgent),.packet_timestamp(packet_timestamp),.timeout_sweep(timeout_close),.current_timestamp_ticks(timestamp_ticks),
  .event_valid(event_valid),.event_ready(event_ready),.base_features_flat(base_features),.event_timestamp_seconds(event_time),.event_dst_ip(event_dst),.event_src_port(event_port),.event_service_code(event_service),.event_flag_code(event_flag),.table_full_error(flow_table_full),.close_event_overflow(close_event_overflow));
 ids_history_pipeline_resource pipeline(.clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_ready(event_ready),.base_features_flat(base_features),.event_timestamp_seconds(event_time),.event_dst_ip(event_dst),.event_src_port(event_port),.event_service_code(event_service),.event_flag_code(event_flag),.raw_record_valid(raw_record_valid),.raw_record_ready(raw_record_ready),.raw_features_flat(raw_features_flat));
 ids_top_live #(.ROM_FILE(ROM_FILE)) classifier(.clk(clk),.rst_n(rst_n),.raw_record_valid(raw_record_valid),.raw_record_ready(raw_record_ready),.raw_features_flat(raw_features_flat),.model_write_en(model_write_en),.model_write_addr(model_write_addr),.model_write_data(model_write_data),.model_activate(model_activate),.busy(busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version));
endmodule

