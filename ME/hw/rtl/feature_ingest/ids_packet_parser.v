// Ethernet-II / IPv4 / TCP-UDP descriptor parser for an 8-bit byte stream.
// VLAN, IPv6 and non-first IP fragments are reported as unsupported.
module ids_packet_parser (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire rx_sop,
    input wire rx_last,
    input wire [63:0] timestamp_ticks,
    output reg descriptor_valid,
    output reg descriptor_error,
    output reg [31:0] src_ip,
    output reg [31:0] dst_ip,
    output reg [15:0] src_port,
    output reg [15:0] dst_port,
    output reg [15:0] frame_bytes,
    output reg [15:0] ip_total_bytes,
    output reg [7:0] ip_protocol,
    output reg [7:0] tcp_flags,
    output reg [1:0] protocol_code,
    output reg [6:0] service_code,
    output reg [3:0] flag_code,
    output reg wrong_fragment,
    output reg urgent,
    output reg [63:0] packet_timestamp
);
    reg [15:0] byte_index;
    reg [15:0] ethertype;
    reg [3:0] ip_version;
    reg [3:0] ihl_words;
    reg [15:0] l4_offset;
    reg [12:0] fragment_offset;
    wire [15:0] current_index;

    assign current_index = rx_sop ? 16'd0 : byte_index;

    function [6:0] port_to_service;
        input [15:0] port;
        input [7:0] protocol;
        begin
            if (protocol == 8'd17 && port == 16'd53)
                port_to_service = 7'd13; // domain_u
            else begin
                case (port)
                    16'd20:  port_to_service = 7'd21; // ftp_data
                    16'd21:  port_to_service = 7'd20; // ftp
                    16'd22:  port_to_service = 7'd57; // ssh
                    16'd23:  port_to_service = 7'd61; // telnet
                    16'd25:  port_to_service = 7'd55; // smtp
                    16'd53:  port_to_service = 7'd12; // domain
                    16'd80:  port_to_service = 7'd25; // http
                    16'd110: port_to_service = 7'd48; // pop_3
                    16'd143: port_to_service = 7'd29; // imap4
                    16'd443: port_to_service = 7'd27; // http_443
                    default: port_to_service = 7'd45; // other
                endcase
            end
        end
    endfunction

    function [3:0] tcp_to_flag_code;
        input [7:0] flags;
        input [7:0] protocol;
        begin
            if (protocol != 8'd6)
                tcp_to_flag_code = 4'd1;       // OTH
            else if (flags[2])
                tcp_to_flag_code = 4'd3;       // RSTO
            else if (flags[1] && !flags[4])
                tcp_to_flag_code = 4'd6;       // SYN without ACK -> S0
            else if (flags[0] || flags[4])
                tcp_to_flag_code = 4'd10;      // FIN/ACK -> SF
            else
                tcp_to_flag_code = 4'd1;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_index <= 16'd0;
            descriptor_valid <= 1'b0;
            descriptor_error <= 1'b0;
            src_ip <= 32'd0; dst_ip <= 32'd0;
            src_port <= 16'd0; dst_port <= 16'd0;
            frame_bytes <= 16'd0; ip_total_bytes <= 16'd0;
            ip_protocol <= 8'd0; tcp_flags <= 8'd0;
            protocol_code <= 2'd0; service_code <= 7'd0; flag_code <= 4'd0;
            wrong_fragment <= 1'b0; urgent <= 1'b0;
            packet_timestamp <= 64'd0;
            ethertype <= 16'd0; ip_version <= 4'd0; ihl_words <= 4'd0;
            l4_offset <= 16'd34; fragment_offset <= 13'd0;
        end else begin
            descriptor_valid <= 1'b0;
            if (rx_valid) begin
                if (rx_sop) begin
                    descriptor_error <= 1'b0;
                    src_ip <= 32'd0; dst_ip <= 32'd0;
                    src_port <= 16'd0; dst_port <= 16'd0;
                    tcp_flags <= 8'd0; fragment_offset <= 13'd0;
                    packet_timestamp <= timestamp_ticks;
                end
                case (current_index)
                    16'd12: ethertype[15:8] <= rx_data;
                    16'd13: ethertype[7:0] <= rx_data;
                    16'd14: begin
                        ip_version <= rx_data[7:4];
                        ihl_words <= rx_data[3:0];
                        l4_offset <= 16'd14 + ({12'd0, rx_data[3:0]} << 2);
                    end
                    16'd16: ip_total_bytes[15:8] <= rx_data;
                    16'd17: ip_total_bytes[7:0] <= rx_data;
                    16'd20: fragment_offset[12:8] <= rx_data[4:0];
                    16'd21: fragment_offset[7:0] <= rx_data;
                    16'd23: ip_protocol <= rx_data;
                    16'd26: src_ip[31:24] <= rx_data;
                    16'd27: src_ip[23:16] <= rx_data;
                    16'd28: src_ip[15:8] <= rx_data;
                    16'd29: src_ip[7:0] <= rx_data;
                    16'd30: dst_ip[31:24] <= rx_data;
                    16'd31: dst_ip[23:16] <= rx_data;
                    16'd32: dst_ip[15:8] <= rx_data;
                    16'd33: dst_ip[7:0] <= rx_data;
                endcase
                if (current_index == l4_offset)
                    src_port[15:8] <= rx_data;
                if (current_index == l4_offset + 1)
                    src_port[7:0] <= rx_data;
                if (current_index == l4_offset + 2)
                    dst_port[15:8] <= rx_data;
                if (current_index == l4_offset + 3)
                    dst_port[7:0] <= rx_data;
                if (current_index == l4_offset + 13)
                    tcp_flags <= rx_data;

                byte_index <= current_index + 1'b1;
                if (rx_last) begin
                    frame_bytes <= current_index + 1'b1;
                    descriptor_error <= (ethertype != 16'h0800) || (ip_version != 4'd4) ||
                                        (ihl_words < 4'd5) || (fragment_offset != 13'd0);
                    descriptor_valid <= (ethertype == 16'h0800) && (ip_version == 4'd4) &&
                                        (ihl_words >= 4'd5) && (fragment_offset == 13'd0);
                    if (ip_protocol == 8'd1)
                        protocol_code <= 2'd1;
                    else if (ip_protocol == 8'd6)
                        protocol_code <= 2'd2;
                    else if (ip_protocol == 8'd17)
                        protocol_code <= 2'd3;
                    else
                        protocol_code <= 2'd0;
                    service_code <= port_to_service(dst_port, ip_protocol);
                    flag_code <= tcp_to_flag_code(tcp_flags, ip_protocol);
                    wrong_fragment <= (fragment_offset != 13'd0);
                    urgent <= (ip_protocol == 8'd6) && tcp_flags[5];
                end
            end
        end
    end
endmodule
