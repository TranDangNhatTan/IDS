`timescale 1ns/1ps
// 8-N-1 UART receiver.  A one-clock valid pulse is emitted after each byte.
module uart_rx_byte #(parameter integer CLKS_PER_BIT = 434) (
    input wire clk, input wire rst_n, input wire rx,
    output reg [7:0] data, output reg valid
);
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    reg [1:0] state;
    reg [15:0] count;
    reg [2:0] bit_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; count<=0; bit_index<=0; data<=0; valid<=0; end
        else begin
            valid <= 1'b0;
            case (state)
                IDLE: if (!rx) begin count<=0; state<=START; end
                START: if (count == (CLKS_PER_BIT/2)-1) begin
                    count<=0; state <= rx ? IDLE : DATA; bit_index<=0;
                end else count<=count+1'b1;
                DATA: if (count == CLKS_PER_BIT-1) begin
                    count<=0; data[bit_index]<=rx;
                    if (bit_index==3'd7) state<=STOP; else bit_index<=bit_index+1'b1;
                end else count<=count+1'b1;
                STOP: if (count == CLKS_PER_BIT-1) begin
                    count<=0; state<=IDLE; if (rx) valid<=1'b1;
                end else count<=count+1'b1;
            endcase
        end
    end
endmodule

