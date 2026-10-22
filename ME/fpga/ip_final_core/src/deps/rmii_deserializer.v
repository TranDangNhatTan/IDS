`timescale 1ns/1ps

module rmii_deserializer #(
    // A real PHY presents 7 x 0x55 plus 0xD5 before the Ethernet header.
    // Testbenches that already start at the MAC header can set this to zero.
    parameter integer STRIP_PREAMBLE = 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] rxd,
    input  wire       crs_dv,
    output reg  [7:0] rx_byte,
    output reg        rx_byte_valid,
    output reg        rx_byte_sop,
    output reg        rx_byte_last,
    output reg        rx_frame_error
);
    reg       in_frame;
    reg [1:0] dibit_count;
    reg [7:0] assemble_byte;
    reg [7:0] pending_byte;
    reg       pending_valid;
    reg [8:0] physical_byte_count;
    reg       data_started;

    wire [7:0] completed_byte = {
        rxd,
        assemble_byte[5:0]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_frame       <= 1'b0;
            dibit_count    <= 2'd0;
            assemble_byte  <= 8'd0;
            pending_byte   <= 8'd0;
            pending_valid  <= 1'b0;
            physical_byte_count <= 9'd0;
            data_started   <= 1'b0;
            rx_byte        <= 8'd0;
            rx_byte_valid  <= 1'b0;
            rx_byte_sop    <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;
        end else begin
            rx_byte_valid  <= 1'b0;
            rx_byte_sop    <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;

            if (crs_dv) begin
                if (!in_frame) begin
                    in_frame <= 1'b1;
                    physical_byte_count <= 9'd0;
                    pending_valid <= 1'b0;
                    dibit_count <= 2'd0;
                    data_started <= 1'b0;
                end
                case (dibit_count)
                    2'd0: assemble_byte[1:0] <= rxd;
                    2'd1: assemble_byte[3:2] <= rxd;
                    2'd2: assemble_byte[5:4] <= rxd;
                    2'd3: begin
                        // pending_byte is one physical byte behind.  Do not
                        // expose physical bytes 0..7 (preamble + SFD).
                        if (pending_valid && (!STRIP_PREAMBLE || physical_byte_count > 9'd8)) begin
                            rx_byte       <= pending_byte;
                            rx_byte_valid <= 1'b1;
                            if (!data_started) begin rx_byte_sop<=1'b1; data_started<=1'b1; end
                            rx_byte_last  <= 1'b0;
                        end
                        pending_byte  <= completed_byte;
                        pending_valid <= 1'b1;
                        physical_byte_count <= physical_byte_count + 1'b1;
                    end
                endcase

                if (dibit_count == 2'd3)
                    dibit_count <= 2'd0;
                else
                    dibit_count <= dibit_count + 2'd1;
            end else if (in_frame) begin
                in_frame <= 1'b0;
                if (dibit_count != 2'd0) begin
                    rx_frame_error <= 1'b1;
                    pending_valid  <= 1'b0;
                    dibit_count    <= 2'd0;
                end else if (pending_valid) begin
                    if (!STRIP_PREAMBLE || physical_byte_count > 9'd8) begin
                        rx_byte       <= pending_byte;
                        rx_byte_valid <= 1'b1;
                        if (!data_started) begin rx_byte_sop<=1'b1; data_started<=1'b1; end
                        rx_byte_last  <= 1'b1;
                    end
                    pending_valid <= 1'b0;
                end
            end
        end
    end
endmodule



