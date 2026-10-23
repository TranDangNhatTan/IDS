`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg  [7:0] rx_data,
    output reg        rx_done,
    output reg        framing_error
);
    localparam integer CLKS_PER_BIT =
        (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;

    function integer clog2;
        input integer value;
        integer work;
        begin
            work = value - 1;
            for (clog2 = 0; work > 0; clog2 = clog2 + 1)
                work = work >> 1;
        end
    endfunction

    localparam integer COUNT_WIDTH =
        (clog2(CLKS_PER_BIT) < 1) ? 1 : clog2(CLKS_PER_BIT);
    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] START_CHECK = 3'd1;
    localparam [2:0] DATA        = 3'd2;
    localparam [2:0] STOP        = 3'd3;
    localparam [2:0] WAIT_IDLE   = 3'd4;

    // Exactly two flip-flops synchronize the asynchronous UART input.
    reg rx_meta;
    reg rx_sync;
    reg rx_history;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta    <= 1'b1;
            rx_sync    <= 1'b1;
            rx_history <= 1'b1;
        end else begin
            rx_meta    <= uart_rx;
            rx_sync    <= rx_meta;
            rx_history <= rx_sync;
        end
    end
    wire start_edge = rx_history && !rx_sync;

    reg [2:0] state;
    reg [COUNT_WIDTH-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            baud_count    <= {COUNT_WIDTH{1'b0}};
            bit_index     <= 3'd0;
            shift_reg     <= 8'h00;
            rx_data       <= 8'h00;
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
            case (state)
                IDLE: begin
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;
                    if (start_edge)
                        state <= START_CHECK;
                end

                START_CHECK: begin
                    if (baud_count == HALF_CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        if (!rx_sync) begin
                            shift_reg <= 8'h00;
                            bit_index <= 3'd0;
                            state     <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count           <= {COUNT_WIDTH{1'b0}};
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        if (rx_sync) begin
                            rx_data <= shift_reg;
                            rx_done <= 1'b1;
                            state   <= IDLE;
                        end else begin
                            framing_error <= 1'b1;
                            state         <= WAIT_IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                WAIT_IDLE: begin
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    if (rx_sync)
                        state <= IDLE;
                end

                default: begin
                    state      <= IDLE;
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;
                end
            endcase
        end
    end
endmodule
