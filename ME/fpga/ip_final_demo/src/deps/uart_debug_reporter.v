`timescale 1ns/1ps

// Emits "DBG=hhhh\r\n" periodically, where hhhh is a 16-bit status word.
module uart_debug_reporter #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer REPORT_CYCLES = 50000000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] status,
    output wire        uart_tx
);
    reg [31:0] report_count;
    reg [3:0]  char_index;
    reg [15:0] status_latched;
    reg [7:0]  tx_data;
    reg        tx_start;
    reg        report_active;
    wire       tx_busy;
    wire       tx_done;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin
            hex_ascii = (nibble < 10) ? (8'h30 + nibble) :
                                        (8'h41 + nibble - 10);
        end
    endfunction

    function [7:0] report_byte;
        input [3:0] index;
        input [15:0] value;
        begin
            case (index)
                4'd0: report_byte = "D";
                4'd1: report_byte = "B";
                4'd2: report_byte = "G";
                4'd3: report_byte = "=";
                4'd4: report_byte = hex_ascii(value[15:12]);
                4'd5: report_byte = hex_ascii(value[11:8]);
                4'd6: report_byte = hex_ascii(value[7:4]);
                4'd7: report_byte = hex_ascii(value[3:0]);
                4'd8: report_byte = 8'h0D;
                default: report_byte = 8'h0A;
            endcase
        end
    endfunction

    uart_tx_byte #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_tx_byte (
        .clk(clk),
        .rst_n(rst_n),
        .start(tx_start),
        .data(tx_data),
        .tx(uart_tx),
        .busy(tx_busy),
        .done(tx_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            report_count   <= REPORT_CYCLES - 1;
            char_index     <= 4'd0;
            status_latched <= 16'd0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
            report_active  <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (!report_active) begin
                if (report_count == REPORT_CYCLES - 1) begin
                    report_count   <= 32'd0;
                    char_index     <= 4'd0;
                    status_latched <= status;
                    report_active  <= 1'b1;
                end else begin
                    report_count <= report_count + 1'b1;
                end
            end else if (!tx_busy && !tx_start) begin
                tx_data  <= report_byte(char_index, status_latched);
                tx_start <= 1'b1;
                if (char_index == 4'd9) begin
                    report_active <= 1'b0;
                end else begin
                    char_index <= char_index + 1'b1;
                end
            end
        end
    end
endmodule


