// Small fully-associative reference flow table. One packet update is accepted
// per cycle. A production implementation can replace the lookup with hashed
// BRAM banks while preserving this module's record/history contract.
module ids_flow_table #(
    parameter FLOW_ENTRIES = 16,
    parameter TICKS_PER_SECOND = 100000000,
    parameter FLOW_TIMEOUT_TICKS = 500000000
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
    input wire timeout_sweep,
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
    output reg table_full_error
);
    reg valid_mem [0:FLOW_ENTRIES-1];
    reg [31:0] src_ip_mem [0:FLOW_ENTRIES-1];
    reg [31:0] dst_ip_mem [0:FLOW_ENTRIES-1];
    reg [15:0] src_port_mem [0:FLOW_ENTRIES-1];
    reg [15:0] dst_port_mem [0:FLOW_ENTRIES-1];
    reg [7:0] protocol_mem [0:FLOW_ENTRIES-1];
    reg [1:0] protocol_code_mem [0:FLOW_ENTRIES-1];
    reg [6:0] service_mem [0:FLOW_ENTRIES-1];
    reg [3:0] flag_mem [0:FLOW_ENTRIES-1];
    reg [63:0] start_time_mem [0:FLOW_ENTRIES-1];
    reg [63:0] last_time_mem [0:FLOW_ENTRIES-1];
    reg [31:0] src_bytes_mem [0:FLOW_ENTRIES-1];
    reg [31:0] dst_bytes_mem [0:FLOW_ENTRIES-1];
    reg [2:0] fragment_mem [0:FLOW_ENTRIES-1];
    reg urgent_mem [0:FLOW_ENTRIES-1];
    integer scan_pointer;
    integer search_i;
    integer reset_i;
    integer match_index;
    integer free_index;
    reg match_found;
    reg match_reverse;
    reg free_found;

    reg close_valid;
    integer close_index;
    reg close_from_packet;
    wire output_available;
    wire packet_requests_close;
    wire [63:0] selected_close_time;
    wire [31:0] selected_src_bytes;
    wire [31:0] selected_dst_bytes;
    wire [2:0] selected_fragment_count;
    wire selected_urgent;
    wire [3:0] selected_flag;
    // Keep division results 64-bit until the explicit feature-contract cast.
    // The 32-bit fields represent seconds, so overflow is only possible after
    // about 136 years at one-second resolution.
    wire [63:0] selected_close_seconds;
    wire [63:0] selected_duration_seconds;

    assign output_available = !raw_record_valid || raw_record_ready;
    assign packet_requests_close = packet_valid && match_found && ip_protocol == 8'd6 &&
                                   (tcp_flags[0] || tcp_flags[2]);
    assign packet_ready = output_available && (match_found || free_found);

    always @* begin
        match_found = 1'b0;
        match_reverse = 1'b0;
        match_index = 0;
        free_found = 1'b0;
        free_index = 0;
        for (search_i = 0; search_i < FLOW_ENTRIES; search_i = search_i + 1) begin
            if (!valid_mem[search_i] && !free_found) begin
                free_found = 1'b1;
                free_index = search_i;
            end
            if (valid_mem[search_i] && !match_found) begin
                if (src_ip == src_ip_mem[search_i] && dst_ip == dst_ip_mem[search_i] &&
                    src_port == src_port_mem[search_i] && dst_port == dst_port_mem[search_i] &&
                    ip_protocol == protocol_mem[search_i]) begin
                    match_found = 1'b1;
                    match_reverse = 1'b0;
                    match_index = search_i;
                end else if (src_ip == dst_ip_mem[search_i] && dst_ip == src_ip_mem[search_i] &&
                             src_port == dst_port_mem[search_i] && dst_port == src_port_mem[search_i] &&
                             ip_protocol == protocol_mem[search_i]) begin
                    match_found = 1'b1;
                    match_reverse = 1'b1;
                    match_index = search_i;
                end
            end
        end
    end

    always @* begin
        close_valid = 1'b0;
        close_index = 0;
        close_from_packet = 1'b0;
        if (packet_requests_close) begin
            close_valid = 1'b1;
            close_index = match_index;
            close_from_packet = 1'b1;
        end else if (timeout_sweep && valid_mem[scan_pointer] &&
                     current_timestamp_ticks >= last_time_mem[scan_pointer] &&
                     current_timestamp_ticks - last_time_mem[scan_pointer] >= FLOW_TIMEOUT_TICKS) begin
            close_valid = 1'b1;
            close_index = scan_pointer;
            close_from_packet = 1'b0;
        end
    end

    assign selected_close_time = close_from_packet ? packet_timestamp : current_timestamp_ticks;
    assign selected_src_bytes = src_bytes_mem[close_index] +
                                ((close_from_packet && !match_reverse) ? frame_bytes : 0);
    assign selected_dst_bytes = dst_bytes_mem[close_index] +
                                ((close_from_packet && match_reverse) ? frame_bytes : 0);
    assign selected_fragment_count = fragment_mem[close_index] +
                                     ((close_from_packet && wrong_fragment && fragment_mem[close_index] < 7) ? 1'b1 : 1'b0);
    assign selected_urgent = urgent_mem[close_index] || (close_from_packet && urgent);
    assign selected_flag = close_from_packet ? flag_code : flag_mem[close_index];

    assign history_query_valid = close_valid && output_available;
    assign history_commit = history_query_valid;
    assign selected_close_seconds = selected_close_time / TICKS_PER_SECOND;
    assign selected_duration_seconds = (selected_close_time >= start_time_mem[close_index]) ?
                                       ((selected_close_time - start_time_mem[close_index]) / TICKS_PER_SECOND) : 64'd0;
    assign history_timestamp_seconds = selected_close_seconds[31:0];
    assign history_dst_ip = dst_ip_mem[close_index];
    assign history_src_port = src_port_mem[close_index];
    assign history_service_code = service_mem[close_index];
    assign history_flag_code = selected_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_record_valid <= 1'b0;
            raw_features_flat <= {28*32{1'b0}};
            table_full_error <= 1'b0;
            scan_pointer <= 0;
            for (reset_i = 0; reset_i < FLOW_ENTRIES; reset_i = reset_i + 1)
                valid_mem[reset_i] <= 1'b0;
        end else begin
            table_full_error <= 1'b0;
            if (raw_record_valid && raw_record_ready)
                raw_record_valid <= 1'b0;
            if (timeout_sweep) begin
                if (scan_pointer == FLOW_ENTRIES-1)
                    scan_pointer <= 0;
                else
                    scan_pointer <= scan_pointer + 1;
            end

            if (close_valid && output_available) begin
                raw_features_flat <= {28*32{1'b0}};
                raw_features_flat[0*32 +: 32] <= selected_duration_seconds[31:0];
                raw_features_flat[1*32 +: 32] <= protocol_code_mem[close_index];
                raw_features_flat[2*32 +: 32] <= service_mem[close_index];
                raw_features_flat[3*32 +: 32] <= selected_flag;
                raw_features_flat[4*32 +: 32] <= selected_src_bytes;
                raw_features_flat[5*32 +: 32] <= selected_dst_bytes;
                raw_features_flat[6*32 +: 32] <= src_ip_mem[close_index] == dst_ip_mem[close_index] &&
                                                      src_port_mem[close_index] == dst_port_mem[close_index];
                raw_features_flat[7*32 +: 32] <= selected_fragment_count;
                raw_features_flat[8*32 +: 32] <= selected_urgent;
                raw_features_flat[9*32 +: 19*32] <= history_features_flat;
                raw_record_valid <= 1'b1;
                valid_mem[close_index] <= 1'b0;
            end else if (packet_valid && output_available) begin
                if (match_found) begin
                    last_time_mem[match_index] <= packet_timestamp;
                    flag_mem[match_index] <= flag_code;
                    if (match_reverse)
                        dst_bytes_mem[match_index] <= dst_bytes_mem[match_index] + frame_bytes;
                    else
                        src_bytes_mem[match_index] <= src_bytes_mem[match_index] + frame_bytes;
                    if (wrong_fragment && fragment_mem[match_index] < 7)
                        fragment_mem[match_index] <= fragment_mem[match_index] + 1'b1;
                    urgent_mem[match_index] <= urgent_mem[match_index] || urgent;
                end else if (free_found) begin
                    valid_mem[free_index] <= 1'b1;
                    src_ip_mem[free_index] <= src_ip; dst_ip_mem[free_index] <= dst_ip;
                    src_port_mem[free_index] <= src_port; dst_port_mem[free_index] <= dst_port;
                    protocol_mem[free_index] <= ip_protocol;
                    protocol_code_mem[free_index] <= protocol_code;
                    service_mem[free_index] <= service_code; flag_mem[free_index] <= flag_code;
                    start_time_mem[free_index] <= packet_timestamp;
                    last_time_mem[free_index] <= packet_timestamp;
                    src_bytes_mem[free_index] <= frame_bytes; dst_bytes_mem[free_index] <= 0;
                    fragment_mem[free_index] <= wrong_fragment ? 1 : 0;
                    urgent_mem[free_index] <= urgent;
                end else begin
                    table_full_error <= 1'b1;
                end
            end
        end
    end
endmodule
