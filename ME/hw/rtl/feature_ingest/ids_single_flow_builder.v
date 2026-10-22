// One-active-flow reference builder. It demonstrates the packet-to-feature
// contract and is simulation-ready. Scale to a hashed multi-entry flow table
// by replicating this state behind a key lookup/hazard controller.
module ids_single_flow_builder #(
    parameter TICKS_PER_SECOND = 100000000
) (
    input wire clk,
    input wire rst_n,
    input wire packet_valid,
    output wire packet_ready,
    input wire [31:0] src_ip,
    input wire [31:0] dst_ip,
    input wire [15:0] src_port,
    input wire [15:0] dst_port,
    input wire [15:0] frame_bytes,
    input wire [7:0] ip_protocol,
    input wire [7:0] tcp_flags,
    input wire [1:0] protocol_code,
    input wire [6:0] service_code,
    input wire [3:0] flag_code,
    input wire wrong_fragment,
    input wire urgent,
    input wire [63:0] packet_timestamp,
    input wire timeout_close,
    input wire [63:0] current_timestamp_ticks,
    input wire [19*32-1:0] history_features_flat,
    output wire history_query_valid,
    output wire history_commit,
    output wire [31:0] history_timestamp_seconds,
    output wire [31:0] history_dst_ip,
    output wire [15:0] history_src_port,
    output wire [6:0] history_service_code,
    output wire [3:0] history_flag_code,
    output reg raw_record_valid,
    input wire raw_record_ready,
    output reg [28*32-1:0] raw_features_flat,
    output reg collision_error
);
    reg active;
    reg [31:0] flow_src_ip, flow_dst_ip;
    reg [15:0] flow_src_port, flow_dst_port;
    reg [7:0] flow_protocol;
    reg [1:0] flow_protocol_code;
    reg [6:0] flow_service_code;
    reg [3:0] flow_flag_code;
    reg [63:0] start_timestamp;
    reg [31:0] src_bytes_count, dst_bytes_count;
    reg [2:0] fragment_count;
    reg urgent_seen;

    wire forward_match;
    wire reverse_match;
    wire matching_packet;
    wire tcp_close;
    wire close_event;
    wire output_available;
    wire [63:0] close_timestamp;
    wire [31:0] close_seconds;
    wire [31:0] duration_seconds;
    wire [31:0] final_src_bytes;
    wire [31:0] final_dst_bytes;
    wire [2:0] final_fragment_count;
    wire final_urgent;
    wire [3:0] final_flag_code;

    assign forward_match = active && src_ip == flow_src_ip && dst_ip == flow_dst_ip &&
                           src_port == flow_src_port && dst_port == flow_dst_port && ip_protocol == flow_protocol;
    assign reverse_match = active && src_ip == flow_dst_ip && dst_ip == flow_src_ip &&
                           src_port == flow_dst_port && dst_port == flow_src_port && ip_protocol == flow_protocol;
    assign matching_packet = forward_match || reverse_match;
    assign tcp_close = packet_valid && matching_packet && ip_protocol == 8'd6 && (tcp_flags[0] || tcp_flags[2]);
    assign close_event = active && (timeout_close || tcp_close);
    assign output_available = !raw_record_valid || raw_record_ready;
    assign packet_ready = output_available;
    assign close_timestamp = tcp_close ? packet_timestamp : current_timestamp_ticks;
    assign close_seconds = close_timestamp / TICKS_PER_SECOND;
    assign duration_seconds = (close_timestamp >= start_timestamp) ?
                              ((close_timestamp - start_timestamp) / TICKS_PER_SECOND) : 0;
    assign final_src_bytes = src_bytes_count + ((tcp_close && forward_match) ? frame_bytes : 0);
    assign final_dst_bytes = dst_bytes_count + ((tcp_close && reverse_match) ? frame_bytes : 0);
    assign final_fragment_count = fragment_count + ((tcp_close && wrong_fragment && fragment_count < 7) ? 1'b1 : 1'b0);
    assign final_urgent = urgent_seen || (tcp_close && urgent);
    assign final_flag_code = tcp_close ? flag_code : flow_flag_code;

    assign history_query_valid = close_event && output_available;
    assign history_commit = history_query_valid;
    assign history_timestamp_seconds = close_seconds;
    assign history_dst_ip = flow_dst_ip;
    assign history_src_port = flow_src_port;
    assign history_service_code = flow_service_code;
    assign history_flag_code = final_flag_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            raw_record_valid <= 1'b0;
            raw_features_flat <= {28*32{1'b0}};
            collision_error <= 1'b0;
            flow_src_ip <= 0; flow_dst_ip <= 0;
            flow_src_port <= 0; flow_dst_port <= 0; flow_protocol <= 0;
            flow_protocol_code <= 0; flow_service_code <= 0; flow_flag_code <= 0;
            start_timestamp <= 0; src_bytes_count <= 0; dst_bytes_count <= 0;
            fragment_count <= 0; urgent_seen <= 0;
        end else begin
            collision_error <= 1'b0;
            if (raw_record_valid && raw_record_ready)
                raw_record_valid <= 1'b0;

            if (close_event && output_available) begin
                raw_features_flat <= {28*32{1'b0}};
                raw_features_flat[0*32 +: 32] <= duration_seconds;
                raw_features_flat[1*32 +: 32] <= flow_protocol_code;
                raw_features_flat[2*32 +: 32] <= flow_service_code;
                raw_features_flat[3*32 +: 32] <= final_flag_code;
                raw_features_flat[4*32 +: 32] <= final_src_bytes;
                raw_features_flat[5*32 +: 32] <= final_dst_bytes;
                raw_features_flat[6*32 +: 32] <= (flow_src_ip == flow_dst_ip && flow_src_port == flow_dst_port);
                raw_features_flat[7*32 +: 32] <= final_fragment_count;
                raw_features_flat[8*32 +: 32] <= final_urgent;
                raw_features_flat[9*32 +: 19*32] <= history_features_flat;
                raw_record_valid <= 1'b1;
                active <= 1'b0;
            end else if (packet_valid && packet_ready) begin
                if (!active) begin
                    active <= 1'b1;
                    flow_src_ip <= src_ip; flow_dst_ip <= dst_ip;
                    flow_src_port <= src_port; flow_dst_port <= dst_port;
                    flow_protocol <= ip_protocol;
                    flow_protocol_code <= protocol_code;
                    flow_service_code <= service_code;
                    flow_flag_code <= flag_code;
                    start_timestamp <= packet_timestamp;
                    src_bytes_count <= frame_bytes;
                    dst_bytes_count <= 0;
                    fragment_count <= wrong_fragment ? 1 : 0;
                    urgent_seen <= urgent;
                end else if (forward_match) begin
                    src_bytes_count <= src_bytes_count + frame_bytes;
                    flow_flag_code <= flag_code;
                    if (wrong_fragment && fragment_count < 7) fragment_count <= fragment_count + 1'b1;
                    urgent_seen <= urgent_seen || urgent;
                end else if (reverse_match) begin
                    dst_bytes_count <= dst_bytes_count + frame_bytes;
                    flow_flag_code <= flag_code;
                    if (wrong_fragment && fragment_count < 7) fragment_count <= fragment_count + 1'b1;
                    urgent_seen <= urgent_seen || urgent;
                end else begin
                    collision_error <= 1'b1;
                end
            end
        end
    end
endmodule
