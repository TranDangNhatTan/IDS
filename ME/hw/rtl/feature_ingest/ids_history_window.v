// Reference history engine for the 19 NSL-KDD time/host-window features.
// It scans a 256-entry completed-flow history when query_valid is asserted.
// This architecture is intentionally simple for RTL simulation; a production
// design can time-multiplex or bank the history RAM without changing the ports.
module ids_history_window #(
    parameter HISTORY_DEPTH = 256
) (
    input wire clk,
    input wire rst_n,
    input wire query_valid,
    input wire commit,
    input wire [31:0] query_timestamp_seconds,
    input wire [31:0] query_dst_ip,
    input wire [15:0] query_src_port,
    input wire [6:0] query_service_code,
    input wire [3:0] query_flag_code,
    output reg [19*32-1:0] history_features_flat
);
    reg valid_mem [0:HISTORY_DEPTH-1];
    reg [31:0] timestamp_mem [0:HISTORY_DEPTH-1];
    reg [31:0] dst_ip_mem [0:HISTORY_DEPTH-1];
    reg [15:0] src_port_mem [0:HISTORY_DEPTH-1];
    reg [6:0] service_mem [0:HISTORY_DEPTH-1];
    reg [3:0] flag_mem [0:HISTORY_DEPTH-1];
    integer write_pointer;
    integer scan_i;
    integer reset_i;

    integer time_count, time_srv_count;
    integer time_serror, time_srv_serror, time_rerror, time_srv_rerror;
    integer time_same_srv, time_diff_srv, time_srv_diff_host;
    integer host_count, host_srv_count, host_same_src_port;
    integer host_serror, host_srv_serror, host_rerror, host_srv_rerror;
    integer all_srv_count, all_srv_diff_host;

    function is_serror;
        input [3:0] flag;
        begin
            is_serror = (flag == 4'd6) || (flag == 4'd7) || (flag == 4'd8) ||
                        (flag == 4'd9) || (flag == 4'd11);
        end
    endfunction

    function is_rerror;
        input [3:0] flag;
        begin
            is_rerror = (flag == 4'd2) || (flag == 4'd3) ||
                        (flag == 4'd4) || (flag == 4'd5);
        end
    endfunction

    function [31:0] ratio_q016;
        input integer numerator;
        input integer denominator;
        reg [63:0] scaled;
        reg [63:0] quotient;
        reg [63:0] remainder;
        begin
            if (denominator <= 0)
                ratio_q016 = 32'd0;
            else if (numerator >= denominator)
                ratio_q016 = 32'd65535;
            else begin
                scaled = numerator * 64'd65535;
                quotient = scaled / denominator;
                remainder = scaled % denominator;
                if ((remainder * 2 > denominator) ||
                    ((remainder * 2 == denominator) && quotient[0]))
                    quotient = quotient + 1'b1;
                ratio_q016 = quotient[31:0];
            end
        end
    endfunction

    always @* begin
        time_count = 0; time_srv_count = 0;
        time_serror = 0; time_srv_serror = 0;
        time_rerror = 0; time_srv_rerror = 0;
        time_same_srv = 0; time_diff_srv = 0; time_srv_diff_host = 0;
        host_count = 0; host_srv_count = 0; host_same_src_port = 0;
        host_serror = 0; host_srv_serror = 0;
        host_rerror = 0; host_srv_rerror = 0;
        all_srv_count = 0; all_srv_diff_host = 0;
        if (query_valid) begin
            for (scan_i = 0; scan_i < HISTORY_DEPTH; scan_i = scan_i + 1) begin
                if (valid_mem[scan_i]) begin
                    if (service_mem[scan_i] == query_service_code) begin
                        all_srv_count = all_srv_count + 1;
                        if (dst_ip_mem[scan_i] != query_dst_ip)
                            all_srv_diff_host = all_srv_diff_host + 1;
                    end
                    if (dst_ip_mem[scan_i] == query_dst_ip) begin
                        host_count = host_count + 1;
                        if (src_port_mem[scan_i] == query_src_port)
                            host_same_src_port = host_same_src_port + 1;
                        if (is_serror(flag_mem[scan_i])) host_serror = host_serror + 1;
                        if (is_rerror(flag_mem[scan_i])) host_rerror = host_rerror + 1;
                        if (service_mem[scan_i] == query_service_code) begin
                            host_srv_count = host_srv_count + 1;
                            if (is_serror(flag_mem[scan_i])) host_srv_serror = host_srv_serror + 1;
                            if (is_rerror(flag_mem[scan_i])) host_srv_rerror = host_srv_rerror + 1;
                        end
                    end
                    if ((query_timestamp_seconds >= timestamp_mem[scan_i]) &&
                        (query_timestamp_seconds - timestamp_mem[scan_i] <= 2)) begin
                        if (dst_ip_mem[scan_i] == query_dst_ip) begin
                            time_count = time_count + 1;
                            if (service_mem[scan_i] == query_service_code)
                                time_same_srv = time_same_srv + 1;
                            else
                                time_diff_srv = time_diff_srv + 1;
                            if (is_serror(flag_mem[scan_i])) time_serror = time_serror + 1;
                            if (is_rerror(flag_mem[scan_i])) time_rerror = time_rerror + 1;
                        end
                        if (service_mem[scan_i] == query_service_code) begin
                            time_srv_count = time_srv_count + 1;
                            if (dst_ip_mem[scan_i] != query_dst_ip)
                                time_srv_diff_host = time_srv_diff_host + 1;
                            if (is_serror(flag_mem[scan_i])) time_srv_serror = time_srv_serror + 1;
                            if (is_rerror(flag_mem[scan_i])) time_srv_rerror = time_srv_rerror + 1;
                        end
                    end
                end
            end
        end
        history_features_flat = {19*32{1'b0}};
        history_features_flat[0*32 +: 32] = (time_count > 511) ? 32'd511 : time_count;
        history_features_flat[1*32 +: 32] = (time_srv_count > 100) ? 32'd100 : time_srv_count;
        history_features_flat[2*32 +: 32] = ratio_q016(time_serror, time_count);
        history_features_flat[3*32 +: 32] = ratio_q016(time_srv_serror, time_srv_count);
        history_features_flat[4*32 +: 32] = ratio_q016(time_rerror, time_count);
        history_features_flat[5*32 +: 32] = ratio_q016(time_srv_rerror, time_srv_count);
        history_features_flat[6*32 +: 32] = ratio_q016(time_same_srv, time_count);
        history_features_flat[7*32 +: 32] = ratio_q016(time_diff_srv, time_count);
        history_features_flat[8*32 +: 32] = ratio_q016(time_srv_diff_host, time_srv_count);
        history_features_flat[9*32 +: 32] = (host_count > 253) ? 32'd253 : host_count;
        history_features_flat[10*32 +: 32] = (host_srv_count > 255) ? 32'd255 : host_srv_count;
        history_features_flat[11*32 +: 32] = ratio_q016(host_srv_count, host_count);
        history_features_flat[12*32 +: 32] = ratio_q016(host_count-host_srv_count, host_count);
        history_features_flat[13*32 +: 32] = ratio_q016(host_same_src_port, host_count);
        history_features_flat[14*32 +: 32] = ratio_q016(all_srv_diff_host, all_srv_count);
        history_features_flat[15*32 +: 32] = ratio_q016(host_serror, host_count);
        history_features_flat[16*32 +: 32] = ratio_q016(host_srv_serror, host_srv_count);
        history_features_flat[17*32 +: 32] = ratio_q016(host_rerror, host_count);
        history_features_flat[18*32 +: 32] = ratio_q016(host_srv_rerror, host_srv_count);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= 0;
            for (reset_i = 0; reset_i < HISTORY_DEPTH; reset_i = reset_i + 1)
                valid_mem[reset_i] <= 1'b0;
        end else if (commit) begin
            valid_mem[write_pointer] <= 1'b1;
            timestamp_mem[write_pointer] <= query_timestamp_seconds;
            dst_ip_mem[write_pointer] <= query_dst_ip;
            src_port_mem[write_pointer] <= query_src_port;
            service_mem[write_pointer] <= query_service_code;
            flag_mem[write_pointer] <= query_flag_code;
            if (write_pointer == HISTORY_DEPTH-1)
                write_pointer <= 0;
            else
                write_pointer <= write_pointer + 1;
        end
    end
endmodule
