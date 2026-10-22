`timescale 1ns/1ps

module tb_feature_blocks;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer failures = 0;
    integer i;

    reg [31:0] numerator = 0;
    reg [31:0] denominator = 0;
    wire [15:0] rate_q016;
    wire divide_by_zero;

    reg query_valid = 0;
    reg commit = 0;
    reg [31:0] query_timestamp_seconds = 0;
    reg [31:0] query_dst_ip = 0;
    reg [15:0] query_src_port = 0;
    reg [6:0] query_service_code = 0;
    reg [3:0] query_flag_code = 0;
    wire [19*32-1:0] history_features_flat;

    reg [7:0] rx_data = 0;
    reg rx_valid = 0;
    reg rx_sop = 0;
    reg rx_last = 0;
    reg [63:0] timestamp_ticks = 0;
    wire descriptor_valid, descriptor_error;
    wire [31:0] src_ip, dst_ip;
    wire [15:0] src_port, dst_port, frame_bytes, ip_total_bytes;
    wire [7:0] ip_protocol, tcp_flags;
    wire [1:0] protocol_code;
    wire [6:0] service_code;
    wire [3:0] flag_code;
    wire wrong_fragment, urgent;
    wire [63:0] packet_timestamp;
    reg [7:0] packet [0:53];

    always #5 clk = ~clk;

    ids_rate_quantizer rate_dut (
        .numerator(numerator), .denominator(denominator),
        .rate_q016(rate_q016), .divide_by_zero(divide_by_zero)
    );

    ids_history_window history_dut (
        .clk(clk), .rst_n(rst_n), .query_valid(query_valid), .commit(commit),
        .query_timestamp_seconds(query_timestamp_seconds), .query_dst_ip(query_dst_ip),
        .query_src_port(query_src_port), .query_service_code(query_service_code),
        .query_flag_code(query_flag_code), .history_features_flat(history_features_flat)
    );

    ids_packet_parser parser_dut (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_sop(rx_sop), .rx_last(rx_last), .timestamp_ticks(timestamp_ticks),
        .descriptor_valid(descriptor_valid), .descriptor_error(descriptor_error),
        .src_ip(src_ip), .dst_ip(dst_ip), .src_port(src_port), .dst_port(dst_port),
        .frame_bytes(frame_bytes), .ip_total_bytes(ip_total_bytes), .ip_protocol(ip_protocol),
        .tcp_flags(tcp_flags), .protocol_code(protocol_code), .service_code(service_code),
        .flag_code(flag_code), .wrong_fragment(wrong_fragment), .urgent(urgent),
        .packet_timestamp(packet_timestamp)
    );

    initial begin
        // Rate contract: numpy.rint(0.5 * 65535) = 32768 (tie-to-even).
        numerator = 1; denominator = 2; #1;
        if (rate_q016 != 16'd32768 || divide_by_zero) failures = failures + 1;
        numerator = 1; denominator = 3; #1;
        if (rate_q016 != 16'd21845) failures = failures + 1;
        numerator = 0; denominator = 0; #1;
        if (!divide_by_zero || rate_q016 != 0) failures = failures + 1;

        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(negedge clk);

        // Commit one S0 flow, then query the same host/service one second later.
        query_valid = 1'b1; commit = 1'b1;
        query_timestamp_seconds = 1;
        query_dst_ip = 32'h0A000001;
        query_src_port = 16'd12345;
        query_service_code = 7'd25;
        query_flag_code = 4'd6;
        @(posedge clk); #1;
        commit = 1'b0;
        query_timestamp_seconds = 2;
        #1;
        if (history_features_flat[0*32 +: 32] != 1 ||
            history_features_flat[1*32 +: 32] != 1 ||
            history_features_flat[2*32 +: 32] != 65535 ||
            history_features_flat[6*32 +: 32] != 65535 ||
            history_features_flat[9*32 +: 32] != 1 ||
            history_features_flat[13*32 +: 32] != 65535)
            failures = failures + 1;

        // Build one Ethernet/IPv4/TCP SYN+ACK packet to destination port 80.
        for (i = 0; i < 54; i = i + 1) packet[i] = 8'h00;
        packet[12] = 8'h08; packet[13] = 8'h00;
        packet[14] = 8'h45;
        packet[16] = 8'h00; packet[17] = 8'd40;
        packet[22] = 8'd64; packet[23] = 8'd6;
        packet[26] = 8'd192; packet[27] = 8'd168; packet[28] = 8'd1; packet[29] = 8'd10;
        packet[30] = 8'd10; packet[31] = 8'd0; packet[32] = 8'd0; packet[33] = 8'd1;
        packet[34] = 8'h30; packet[35] = 8'h39;
        packet[36] = 8'h00; packet[37] = 8'h50;
        packet[46] = 8'h50; packet[47] = 8'h12;
        timestamp_ticks = 64'd123456;
        for (i = 0; i < 54; i = i + 1) begin
            @(negedge clk);
            rx_data = packet[i]; rx_valid = 1'b1;
            rx_sop = (i == 0); rx_last = (i == 53);
        end
        @(negedge clk);
        rx_valid = 1'b0; rx_sop = 1'b0; rx_last = 1'b0;
        #1;
        if (!descriptor_valid || descriptor_error || src_ip != 32'hC0A8010A ||
            dst_ip != 32'h0A000001 || src_port != 16'd12345 || dst_port != 16'd80 ||
            protocol_code != 2'd2 || service_code != 7'd25 || flag_code != 4'd10 ||
            frame_bytes != 16'd54 || ip_total_bytes != 16'd40 || packet_timestamp != 64'd123456)
            failures = failures + 1;

        if (failures == 0)
            $display("FEATURE_BLOCKS_PASS");
        else
            $display("FEATURE_BLOCKS_FAIL failures=%0d", failures);
        $finish;
    end
endmodule
