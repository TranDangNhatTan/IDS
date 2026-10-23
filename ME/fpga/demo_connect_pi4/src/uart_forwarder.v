`timescale 1ns/1ps

module uart_forwarder #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pi,
    output wire uart_tx_pc
);
    // External reset is asserted asynchronously and released synchronously.
    reg [1:0] reset_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire core_rst_n = reset_sync[1];

    wire [7:0] rx_data;
    wire rx_done;
    wire framing_error;
    reg [7:0] tx_data;
    reg tx_en;
    wire tx_busy;
    wire tx_done;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) receiver (
        .clk(clk),
        .rst_n(core_rst_n),
        .uart_rx(uart_rx_pi),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .framing_error(framing_error)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) transmitter (
        .clk(clk),
        .rst_n(core_rst_n),
        .tx_data(tx_data),
        .tx_en(tx_en),
        .uart_tx(uart_tx_pc),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // Four-byte FIFO decouples RX completion from TX start.  A one-byte
    // register alone is unsafe when rx_done coincides with a busy transmitter.
    reg [7:0] fifo [0:3];
    reg [1:0] write_pointer;
    reg [1:0] read_pointer;
    reg [2:0] fifo_count;

    // Internal sticky diagnostics are retained for simulation/on-chip debug.
    reg framing_error_seen;
    reg overflow_seen;

    wire pop_fifo = (fifo_count != 0) && !tx_busy && !tx_en;
    wire push_fifo = rx_done && ((fifo_count != 4) || pop_fifo);

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            write_pointer      <= 2'd0;
            read_pointer       <= 2'd0;
            fifo_count         <= 3'd0;
            tx_data            <= 8'h00;
            tx_en              <= 1'b0;
            framing_error_seen <= 1'b0;
            overflow_seen      <= 1'b0;
        end else begin
            tx_en <= 1'b0;

            if (pop_fifo) begin
                tx_data      <= fifo[read_pointer];
                read_pointer <= read_pointer + 1'b1;
                tx_en        <= 1'b1;
            end

            if (push_fifo) begin
                fifo[write_pointer] <= rx_data;
                write_pointer       <= write_pointer + 1'b1;
            end

            case ({push_fifo, pop_fifo})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase

            if (framing_error)
                framing_error_seen <= 1'b1;
            if (rx_done && !push_fifo)
                overflow_seen <= 1'b1;
        end
    end

    // tx_done is intentionally available in hierarchy for debug.  It need not
    // drive top-level logic because tx_busy provides the required handshake.
    wire unused_tx_done = tx_done;
endmodule
