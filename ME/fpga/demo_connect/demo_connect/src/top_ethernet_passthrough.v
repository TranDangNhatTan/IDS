`timescale 1ns/1ps

module top_ethernet_passthrough #(
    parameter RESET_CYCLES = 500000
) (
    input  wire       rmii_ref_clk,
    input  wire       ext_rst_n,

    input  wire [1:0] phy1_rxd,
    input  wire       phy1_crs_dv,
    output wire [1:0] phy1_txd,
    output wire       phy1_tx_en,
    output wire       phy1_rst_n,

    input  wire [1:0] phy2_rxd,
    input  wire       phy2_crs_dv,
    output wire [1:0] phy2_txd,
    output wire       phy2_tx_en,
    output wire       phy2_rst_n,

    output wire [5:0] status
);
    reg [19:0] reset_counter;
    reg        phy_reset_done;

    wire internal_rst_n = ext_rst_n && phy_reset_done;
    wire overflow_1_to_2;
    wire underflow_1_to_2;
    wire frame_error_1;
    wire overflow_2_to_1;
    wire underflow_2_to_1;
    wire frame_error_2;

    assign phy1_rst_n = phy_reset_done && ext_rst_n;
    assign phy2_rst_n = phy_reset_done && ext_rst_n;
    assign status = {
        frame_error_2,
        underflow_2_to_1,
        overflow_2_to_1,
        frame_error_1,
        underflow_1_to_2,
        overflow_1_to_2
    };

    always @(posedge rmii_ref_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            reset_counter  <= 20'd0;
            phy_reset_done <= 1'b0;
        end else if (!phy_reset_done) begin
            if (reset_counter == RESET_CYCLES - 1) begin
                phy_reset_done <= 1'b1;
            end else begin
                reset_counter <= reset_counter + 20'd1;
            end
        end
    end

    rmii_packet_bridge u_phy1_to_phy2 (
        .clk(rmii_ref_clk),
        .rst_n(internal_rst_n),
        .rx_d(phy1_rxd),
        .rx_crs_dv(phy1_crs_dv),
        .tx_d(phy2_txd),
        .tx_en(phy2_tx_en),
        .fifo_overflow(overflow_1_to_2),
        .tx_underflow(underflow_1_to_2),
        .rx_frame_error(frame_error_1)
    );

    rmii_packet_bridge u_phy2_to_phy1 (
        .clk(rmii_ref_clk),
        .rst_n(internal_rst_n),
        .rx_d(phy2_rxd),
        .rx_crs_dv(phy2_crs_dv),
        .tx_d(phy1_txd),
        .tx_en(phy1_tx_en),
        .fifo_overflow(overflow_2_to_1),
        .tx_underflow(underflow_2_to_1),
        .rx_frame_error(frame_error_2)
    );
endmodule
