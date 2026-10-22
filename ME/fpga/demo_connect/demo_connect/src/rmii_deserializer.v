`timescale 1ns/1ps

module rmii_deserializer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] rxd,
    input  wire       crs_dv,
    output reg  [7:0] rx_byte,
    output reg        rx_byte_valid,
    output reg        rx_byte_last,
    output reg        rx_frame_error
);
    reg       in_frame;
    reg [1:0] dibit_count;
    reg [7:0] assemble_byte;
    reg [7:0] pending_byte;
    reg       pending_valid;

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
            rx_byte        <= 8'd0;
            rx_byte_valid  <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;
        end else begin
            rx_byte_valid  <= 1'b0;
            rx_byte_last   <= 1'b0;
            rx_frame_error <= 1'b0;

            if (crs_dv) begin
                in_frame <= 1'b1;
                case (dibit_count)
                    2'd0: assemble_byte[1:0] <= rxd;
                    2'd1: assemble_byte[3:2] <= rxd;
                    2'd2: assemble_byte[5:4] <= rxd;
                    2'd3: begin
                        if (pending_valid) begin
                            rx_byte       <= pending_byte;
                            rx_byte_valid <= 1'b1;
                            rx_byte_last  <= 1'b0;
                        end
                        pending_byte  <= completed_byte;
                        pending_valid <= 1'b1;
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
                    rx_byte       <= pending_byte;
                    rx_byte_valid <= 1'b1;
                    rx_byte_last  <= 1'b1;
                    pending_valid <= 1'b0;
                end
            end
        end
    end
endmodule
