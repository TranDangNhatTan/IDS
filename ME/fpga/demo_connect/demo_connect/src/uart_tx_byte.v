`timescale 1ns/1ps

// 8-N-1 UART transmitter for one byte at a time.
module uart_tx_byte #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done
);
    reg [15:0] clock_count;
    reg [3:0]  bit_index;
    reg [7:0]  data_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx           <= 1'b1;
            busy         <= 1'b0;
            done         <= 1'b0;
            clock_count  <= 16'd0;
            bit_index    <= 4'd0;
            data_latched <= 8'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                tx          <= 1'b1;
                clock_count <= 16'd0;
                bit_index   <= 4'd0;
                if (start) begin
                    data_latched <= data;
                    tx           <= 1'b0;
                    busy         <= 1'b1;
                end
            end else if (clock_count == CLKS_PER_BIT - 1) begin
                clock_count <= 16'd0;
                if (bit_index < 8) begin
                    tx        <= data_latched[bit_index];
                    bit_index <= bit_index + 1'b1;
                end else if (bit_index == 8) begin
                    tx        <= 1'b1;
                    bit_index <= 4'd9;
                end else begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end else begin
                clock_count <= clock_count + 1'b1;
            end
        end
    end
endmodule
