`timescale 1ns/1ps

module rmii_packet_bridge #(
    parameter FIFO_DEPTH  = 2048,
    parameter FIFO_ADDR_W = 11
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] rx_d,
    input  wire       rx_crs_dv,
    output wire [1:0] tx_d,
    output wire       tx_en,
    output wire       fifo_overflow,
    output wire       tx_underflow,
    output wire       rx_frame_error
);
    wire [7:0] rx_byte;
    wire       rx_byte_valid;
    wire       rx_byte_last;
    wire [7:0] fifo_data;
    wire       fifo_last;
    wire       fifo_valid;
    wire       fifo_full;
    wire       fifo_empty;
    wire       packet_available;
    wire       fifo_rd_en;
    wire [FIFO_ADDR_W:0] fifo_level;
    wire       tx_busy;

    rmii_deserializer u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rxd(rx_d),
        .crs_dv(rx_crs_dv),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid),
        .rx_byte_last(rx_byte_last),
        .rx_frame_error(rx_frame_error)
    );

    fifo_packet_buffer #(
        .DEPTH(FIFO_DEPTH),
        .ADDR_W(FIFO_ADDR_W)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(rx_byte_valid),
        .wr_data(rx_byte),
        .wr_last(rx_byte_last),
        .full(fifo_full),
        .overflow(fifo_overflow),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_data),
        .rd_last(fifo_last),
        .rd_valid(fifo_valid),
        .empty(fifo_empty),
        .packet_available(packet_available),
        .level(fifo_level)
    );

    rmii_serializer u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_data(fifo_data),
        .fifo_last(fifo_last),
        .fifo_valid(fifo_valid),
        .fifo_empty(fifo_empty),
        .packet_available(packet_available),
        .fifo_rd_en(fifo_rd_en),
        .txd(tx_d),
        .tx_en(tx_en),
        .busy(tx_busy),
        .underflow(tx_underflow)
    );
endmodule
