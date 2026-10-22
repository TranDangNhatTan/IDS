`timescale 1ns/1ps

module rgmii_100_deserializer (
    input  wire       rx_clk,
    input  wire       rst_n,
    input  wire [3:0] rxd,
    input  wire       rx_ctl,
    output reg  [7:0] rx_byte,
    output reg        rx_byte_valid,
    output reg        rx_byte_last,
    output reg        rx_frame_error
);
    reg       in_frame;
    reg       high_nibble;
    reg [3:0] low_nibble;
    reg [7:0] pending_byte;
    reg       pending_valid;

    always @(posedge rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            in_frame       <= 1'b0;
            high_nibble    <= 1'b0;
            low_nibble     <= 4'd0;
            pending_byte   <= 8'd0;
            pending_valid  <= 1'b0;
            rx_byte        <= 8'd0;
            rx_byte_valid  <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;
        end else begin
            rx_byte_valid  <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;

            if (rx_ctl) begin
                in_frame <= 1'b1;
                if (!high_nibble) begin
                    low_nibble  <= rxd;
                    high_nibble <= 1'b1;
                end else begin
                    if (pending_valid) begin
                        rx_byte       <= pending_byte;
                        rx_byte_valid <= 1'b1;
                    end
                    pending_byte  <= {rxd, low_nibble};
                    pending_valid <= 1'b1;
                    high_nibble   <= 1'b0;
                end
            end else if (in_frame) begin
                in_frame <= 1'b0;
                if (high_nibble) begin
                    high_nibble    <= 1'b0;
                    pending_valid  <= 1'b0;
                    rx_frame_error <= 1'b1;
                end else if (pending_valid) begin
                    rx_byte       <= pending_byte;
                    rx_byte_valid <= 1'b1;
                    rx_byte_last  <= 1'b1;
                    pending_valid <= 1'b0;
                end
            end
        end
    end
endmodule

