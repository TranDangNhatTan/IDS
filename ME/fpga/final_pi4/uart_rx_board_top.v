`timescale 1ns/1ps

// Board-integration wrapper used only for the programmable bitstream.
// The standalone uart_rx core remains exactly as specified in uart_rx.v.
// Mapping only known onboard LEDs prevents unconstrained core outputs from
// being auto-placed onto unknown package pins.
module uart_rx_board_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire [3:0] led
);
    wire [7:0] received_data;
    wire byte_received;
    wire receive_error;
    reg [25:0] heartbeat;
    reg byte_seen;
    reg error_seen;

    uart_rx receiver (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .rx_data(received_data),
        .rx_done(byte_received),
        .framing_error(receive_error)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat <= 26'd0;
            byte_seen  <= 1'b0;
            error_seen <= 1'b0;
        end else begin
            heartbeat <= heartbeat + 26'd1;
            if (byte_received)
                byte_seen <= 1'b1;
            if (receive_error)
                error_seen <= 1'b1;
        end
    end

    // Keep the received byte implemented without exposing unassigned pins.
    // Its parity modulates the heartbeat LED after each valid byte.
    wire received_parity = ^received_data;
    assign led[0] = heartbeat[25] ^ received_parity;
    assign led[1] = rst_n;
    assign led[2] = byte_seen;
    assign led[3] = error_seen;
endmodule
